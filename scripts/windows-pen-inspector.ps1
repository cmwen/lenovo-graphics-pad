<#
.SYNOPSIS
  Opens a visible Windows Forms canvas and records native WM_POINTER pen events as JSONL.
.DESCRIPTION
  Run on Windows in an interactive session with Windows PowerShell STA, for example:
    powershell.exe -STA -ExecutionPolicy Bypass -File .\scripts\windows-pen-inspector.ps1 -DurationSeconds 30 -OutputPath "$env:TEMP\pen.jsonl"
  Optionally add -EnableMouseInPointer to enable mouse-in-pointer messages inside this process.
  The form records only pointer messages delivered to its own window. It does not install
  hooks, enumerate devices, connect to hardware, or change system settings. Keep the canvas
  in the foreground and draw with the pen for the requested interval. Pressure is logged
  only when Windows reports the pressure field in POINTER_PEN_INFO.penMask.
.PARAMETER DurationSeconds
  Time to keep the canvas open (1 through 120 seconds; default 30).
.PARAMETER OutputPath
  JSON Lines output file. Existing files at this path are replaced.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 120)]
    [int] $DurationSeconds = 30,
    [string] $OutputPath = (Join-Path ([System.IO.Path]::GetTempPath()) ("windows-pen-inspector-{0:yyyyMMdd-HHmmss}.jsonl" -f (Get-Date))),
    [switch] $EnableMouseInPointer
)

$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
    throw 'Run this script in Windows PowerShell with -STA so the visible WinForms canvas can receive input.'
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [IO.Path]::GetDirectoryName($resolvedOutput)
if (-not [IO.Directory]::Exists($outputDirectory)) {
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace WindowsPenInspector {
    [StructLayout(LayoutKind.Sequential)]
    internal struct NativePoint {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PointerInfo {
        public uint PointerType;
        public uint PointerId;
        public uint FrameId;
        public uint PointerFlags;
        public IntPtr SourceDevice;
        public IntPtr HwndTarget;
        public NativePoint PixelLocation;
        public NativePoint HimetricLocation;
        public NativePoint PixelLocationRaw;
        public NativePoint HimetricLocationRaw;
        public uint Time;
        public uint HistoryCount;
        public int InputData;
        public uint KeyStates;
        public ulong PerformanceCount;
        public uint ButtonChangeType;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PointerPenInfo {
        public PointerInfo PointerInfo;
        public uint PenFlags;
        public uint PenMask;
        public uint Pressure;
        public uint Rotation;
        public int TiltX;
        public int TiltY;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct InputMessageSource {
        public uint DeviceType;
        public uint OriginId;
    }

    internal static class NativeMethods {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetPointerType(uint pointerId, out uint pointerType);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetPointerPenInfo(uint pointerId, out PointerPenInfo penInfo);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetCurrentInputMessageSource(out InputMessageSource source);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetMessageExtraInfo();

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool EnableMouseInPointer([MarshalAs(UnmanagedType.Bool)] bool enable);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool IsMouseInPointerEnabled();

        [DllImport("user32.dll")]
        internal static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetForegroundWindow(IntPtr window);
    }

    public sealed class PenCanvas : Form {
        private const int WmPointerUpdate = 0x0245;
        private const int WmPointerDown = 0x0246;
        private const int WmPointerUp = 0x0247;
        private const int WmPointerEnter = 0x0249;
        private const int WmPointerLeave = 0x024A;
        private const int WmMouseMove = 0x0200;
        private const int WmLeftButtonDown = 0x0201;
        private const int WmLeftButtonUp = 0x0202;
        private const uint PtPen = 3;
        private const uint InputMessageDevicePen = 0x00000008;
        private const uint PointerFlagInRange = 0x00000002;
        private const uint PointerFlagInContact = 0x00000004;
        private const uint PenFlagBarrel = 0x00000001;
        private const uint PenFlagInverted = 0x00000002;
        private const uint PenFlagEraser = 0x00000004;
        private const uint PenMaskPressure = 0x00000001;
        private const uint PenMaskRotation = 0x00000002;
        private const uint PenMaskTiltX = 0x00000004;
        private const uint PenMaskTiltY = 0x00000008;
        private const int MaxEvents = 5000;
        private const ulong MousePenSignature = 0xFF515700UL;
        private const ulong MouseSignatureMask = 0xFFFFFF00UL;
        private const ulong MouseTouchFlag = 0x00000080UL;

        private readonly StreamWriter writer;
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly Timer durationTimer = new Timer();
        private readonly Dictionary<string, int> eventCounts = new Dictionary<string, int>();
        private readonly Dictionary<string, int> mouseCounts = new Dictionary<string, int>();
        private readonly List<List<Point>> strokes = new List<List<Point>>();
        private readonly HashSet<uint> distinctPressures = new HashSet<uint>();
        private readonly DateTime startedUtc = DateTime.UtcNow;
        private readonly int durationSeconds;
        private readonly bool mouseInPointerRequested;
        private readonly bool mouseInPointerEnableSucceeded;
        private readonly int mouseInPointerEnableError;
        private int eventCount;
        private int eventRecordsLogged;
        private int penEventCount;
        private int mouseMessageCount;
        private int mouseSourcePenCount;
        private int legacyPenSignatureCount;
        private int legacyTouchSignatureCount;
        private int pressureSampleCount;
        private int nonzeroPressureCount;
        private uint minimumPressure = UInt32.MaxValue;
        private uint maximumPressure;
        private bool limitReached;
        private bool finished;
        private readonly bool mouseInPointerEnabled;
        private List<Point> currentStroke;
        private int drawnPointCount;

        public PenCanvas(string path, int seconds, bool enableRequested, bool enableSucceeded, int enableError) {
            durationSeconds = seconds;
            mouseInPointerRequested = enableRequested;
            mouseInPointerEnableSucceeded = enableSucceeded;
            mouseInPointerEnableError = enableError;
            mouseInPointerEnabled = NativeMethods.IsMouseInPointerEnabled();
            writer = new StreamWriter(path, false, new UTF8Encoding(false));
            writer.AutoFlush = true;

            Text = "Windows native pen event inspector";
            StartPosition = FormStartPosition.Manual;
            Bounds = Screen.PrimaryScreen.WorkingArea;
            WindowState = FormWindowState.Maximized;
            TopMost = true;
            BackColor = Color.White;
            DoubleBuffered = true;
            KeyPreview = true;

            writer.WriteLine("{\"kind\":\"metadata\",\"startedUtc\":\"" + Escape(startedUtc.ToString("o", CultureInfo.InvariantCulture)) +
                "\",\"durationSeconds\":" + durationSeconds.ToString(CultureInfo.InvariantCulture) +
                ",\"maxEventRecords\":" + MaxEvents.ToString(CultureInfo.InvariantCulture) +
                ",\"processArchitecture\":\"" + Escape(Environment.Is64BitProcess ? "x64" : "x86") +
                "\",\"osVersion\":\"" + Escape(Environment.OSVersion.VersionString) +
                "\",\"canvas\":\"This application window only\",\"mouseInPointerRequested\":" + Bool(mouseInPointerRequested) +
                ",\"mouseInPointerEnableSucceeded\":" + Bool(mouseInPointerEnableSucceeded) +
                ",\"mouseInPointerEnableError\":" + mouseInPointerEnableError.ToString(CultureInfo.InvariantCulture) +
                ",\"mouseInPointerEnabled\":" + Bool(mouseInPointerEnabled) +
                ",\"pressureInterpretation\":\"Windows-reported digital value; no physical-pressure claim\"}");

            durationTimer.Interval = seconds * 1000;
            durationTimer.Tick += delegate { durationTimer.Stop(); Close(); };
            Shown += delegate {
                NativeMethods.SetForegroundWindow(Handle);
                Activate();
                BringToFront();
                WriteWindowDiagnostics();
                durationTimer.Start();
            };
            FormClosed += delegate { WriteSummary(); };
        }

        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            using (Font titleFont = new Font("Segoe UI", 17, FontStyle.Bold))
            using (Font bodyFont = new Font("Segoe UI", 10, FontStyle.Regular))
            using (Brush titleBrush = new SolidBrush(Color.FromArgb(35, 55, 80)))
            using (Brush bodyBrush = new SolidBrush(Color.FromArgb(70, 80, 95))) {
                e.Graphics.DrawString("Draw with the pen here", titleFont, titleBrush, 24, 20);
                e.Graphics.DrawString("Native WM_POINTER events are recorded for this window only. " +
                    "Finger and mouse input are not counted. This canvas closes after " + durationSeconds + " seconds.",
                    bodyFont, bodyBrush, new RectangleF(24, 58, ClientSize.Width - 48, 42));
            }
            foreach (List<Point> points in strokes) {
                using (Pen stroke = new Pen(Color.FromArgb(20, 105, 190), 3.0f)) {
                    stroke.StartCap = System.Drawing.Drawing2D.LineCap.Round;
                    stroke.EndCap = System.Drawing.Drawing2D.LineCap.Round;
                    stroke.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                    if (points.Count > 1) e.Graphics.DrawLines(stroke, points.ToArray());
                    else if (points.Count == 1) e.Graphics.DrawEllipse(stroke, points[0].X - 1, points[0].Y - 1, 2, 2);
                }
            }
        }

        protected override void WndProc(ref Message message) {
            if (message.Msg == WmPointerUpdate || message.Msg == WmPointerDown || message.Msg == WmPointerUp ||
                message.Msg == WmPointerEnter || message.Msg == WmPointerLeave) {
                uint pointerId = unchecked((uint)((long)message.WParam & 0xFFFFL));
                uint pointerType;
                if (NativeMethods.GetPointerType(pointerId, out pointerType) && pointerType == PtPen) {
                    PointerPenInfo penInfo;
                    bool havePenInfo = NativeMethods.GetPointerPenInfo(pointerId, out penInfo);
                    LogPointer(message.Msg, pointerId, havePenInfo, havePenInfo ? penInfo : new PointerPenInfo());
                }
            }
            if (message.Msg == WmMouseMove || message.Msg == WmLeftButtonDown || message.Msg == WmLeftButtonUp) {
                LogMouseMessage(message);
            }
            base.WndProc(ref message);
        }

        private void LogPointer(int message, uint pointerId, bool haveInfo, PointerPenInfo penInfo) {
            if (finished) return;
            string name = message == WmPointerDown ? "down" :
                (message == WmPointerUp ? "up" :
                (message == WmPointerEnter ? "enter" :
                (message == WmPointerLeave ? "leave" : "update")));
            if (!eventCounts.ContainsKey(name)) eventCounts[name] = 0;
            eventCounts[name]++;
            penEventCount++;

            uint flags = haveInfo ? penInfo.PointerInfo.PointerFlags : 0;
            uint mask = haveInfo ? penInfo.PenMask : 0;
            uint pressure = haveInfo ? penInfo.Pressure : 0;
            int x = haveInfo ? penInfo.PointerInfo.PixelLocation.X : 0;
            int y = haveInfo ? penInfo.PointerInfo.PixelLocation.Y : 0;
            Point client = haveInfo ? PointToClient(new Point(x, y)) : Point.Empty;
            bool inContact = (flags & PointerFlagInContact) != 0;

            if (haveInfo && (mask & PenMaskPressure) != 0) {
                pressureSampleCount++;
                distinctPressures.Add(pressure);
                if (pressure > 0) nonzeroPressureCount++;
                if (pressure < minimumPressure) minimumPressure = pressure;
                if (pressure > maximumPressure) maximumPressure = pressure;
            }

            if (haveInfo && inContact && client.X >= 0 && client.Y >= 0 && client.X < ClientSize.Width && client.Y < ClientSize.Height) {
                if ((message == WmPointerDown || currentStroke == null) && drawnPointCount < MaxEvents) {
                    currentStroke = new List<Point>();
                    strokes.Add(currentStroke);
                }
                if (currentStroke != null && drawnPointCount < MaxEvents) {
                    currentStroke.Add(client);
                    drawnPointCount++;
                    Invalidate();
                }
            }
            if (message == WmPointerUp || !inContact) currentStroke = null;

            if (eventRecordsLogged >= MaxEvents) {
                limitReached = true;
                return;
            }
            eventCount++;
            eventRecordsLogged++;
            uint nativeTime = haveInfo ? penInfo.PointerInfo.Time : 0;
            int lastError = haveInfo ? 0 : Marshal.GetLastWin32Error();
            string pressureJson = haveInfo && (mask & PenMaskPressure) != 0 ? pressure.ToString(CultureInfo.InvariantCulture) : "null";
            string rotationJson = haveInfo && (mask & PenMaskRotation) != 0 ? penInfo.Rotation.ToString(CultureInfo.InvariantCulture) : "null";
            string tiltXJson = haveInfo && (mask & PenMaskTiltX) != 0 ? penInfo.TiltX.ToString(CultureInfo.InvariantCulture) : "null";
            string tiltYJson = haveInfo && (mask & PenMaskTiltY) != 0 ? penInfo.TiltY.ToString(CultureInfo.InvariantCulture) : "null";
            string line = "{\"kind\":\"pen_event\",\"sequence\":" + eventCount.ToString(CultureInfo.InvariantCulture) +
                ",\"event\":\"" + name + "\",\"pointerId\":" + pointerId.ToString(CultureInfo.InvariantCulture) +
                ",\"pointerType\":\"pen\",\"infoAvailable\":" + Bool(haveInfo) +
                ",\"apiError\":" + lastError.ToString(CultureInfo.InvariantCulture) +
                ",\"pointerFlags\":" + flags.ToString(CultureInfo.InvariantCulture) +
                ",\"pointerFlagsHex\":\"0x" + flags.ToString("X8", CultureInfo.InvariantCulture) + "\"" +
                ",\"penFlags\":" + (haveInfo ? penInfo.PenFlags : 0).ToString(CultureInfo.InvariantCulture) +
                ",\"barrel\":" + Bool(haveInfo && (penInfo.PenFlags & PenFlagBarrel) != 0) +
                ",\"inverted\":" + Bool(haveInfo && (penInfo.PenFlags & PenFlagInverted) != 0) +
                ",\"eraser\":" + Bool(haveInfo && (penInfo.PenFlags & PenFlagEraser) != 0) +
                ",\"inRange\":" + Bool((flags & PointerFlagInRange) != 0) +
                ",\"inContact\":" + Bool(inContact) +
                ",\"penMask\":" + mask.ToString(CultureInfo.InvariantCulture) +
                ",\"pressure\":" + pressureJson +
                ",\"rotation\":" + rotationJson + ",\"tiltX\":" + tiltXJson + ",\"tiltY\":" + tiltYJson +
                ",\"screenX\":" + x.ToString(CultureInfo.InvariantCulture) +
                ",\"screenY\":" + y.ToString(CultureInfo.InvariantCulture) +
                ",\"clientX\":" + client.X.ToString(CultureInfo.InvariantCulture) +
                ",\"clientY\":" + client.Y.ToString(CultureInfo.InvariantCulture) +
                ",\"nativeTimeMs\":" + nativeTime.ToString(CultureInfo.InvariantCulture) +
                ",\"elapsedMs\":" + clock.ElapsedMilliseconds.ToString(CultureInfo.InvariantCulture) +
                ",\"utc\":\"" + Escape(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)) + "\"}";
            writer.WriteLine(line);
        }

        private void LogMouseMessage(Message message) {
            mouseMessageCount++;
            string name = message.Msg == WmMouseMove ? "move" :
                (message.Msg == WmLeftButtonDown ? "left_down" : "left_up");
            if (!mouseCounts.ContainsKey(name)) mouseCounts[name] = 0;
            mouseCounts[name]++;

            InputMessageSource source;
            bool sourceAvailable = NativeMethods.GetCurrentInputMessageSource(out source);
            uint deviceType = sourceAvailable ? source.DeviceType : 0;
            uint originId = sourceAvailable ? source.OriginId : 0;
            ulong extraInfo = unchecked((ulong)NativeMethods.GetMessageExtraInfo().ToInt64());
            bool signatureMatch = (extraInfo & MouseSignatureMask) == MousePenSignature;
            bool touchSignature = signatureMatch && (extraInfo & MouseTouchFlag) != 0;
            bool legacyPenSignature = signatureMatch && !touchSignature;
            bool sourceIdentifiesPen = sourceAvailable && deviceType == InputMessageDevicePen;
            if (sourceIdentifiesPen) mouseSourcePenCount++;
            if (legacyPenSignature) legacyPenSignatureCount++;
            if (touchSignature) legacyTouchSignatureCount++;
            long packed = message.LParam.ToInt64();
            Point client = new Point(unchecked((short)(packed & 0xFFFF)), unchecked((short)((packed >> 16) & 0xFFFF)));
            Point screen = PointToScreen(client);

            if (eventRecordsLogged >= MaxEvents) {
                limitReached = true;
                return;
            }
            eventRecordsLogged++;
            writer.WriteLine("{\"kind\":\"mouse_message\",\"sequence\":" + eventRecordsLogged.ToString(CultureInfo.InvariantCulture) +
                ",\"event\":\"" + name + "\",\"message\":" + message.Msg.ToString(CultureInfo.InvariantCulture) +
                ",\"inputSourceAvailable\":" + Bool(sourceAvailable) +
                ",\"inputDeviceType\":" + deviceType.ToString(CultureInfo.InvariantCulture) +
                ",\"inputOriginId\":" + originId.ToString(CultureInfo.InvariantCulture) +
                ",\"sourceIdentifiesPen\":" + Bool(sourceIdentifiesPen) +
                ",\"extraInfo\":\"0x" + extraInfo.ToString("X", CultureInfo.InvariantCulture) + "\"" +
                ",\"legacyStylusSignature\":" + Bool(signatureMatch) +
                ",\"legacyTouchSignature\":" + Bool(touchSignature) +
                ",\"legacySignatureIdentifiesPen\":" + Bool(legacyPenSignature) +
                ",\"screenX\":" + screen.X.ToString(CultureInfo.InvariantCulture) +
                ",\"screenY\":" + screen.Y.ToString(CultureInfo.InvariantCulture) +
                ",\"clientX\":" + client.X.ToString(CultureInfo.InvariantCulture) +
                ",\"clientY\":" + client.Y.ToString(CultureInfo.InvariantCulture) +
                ",\"elapsedMs\":" + clock.ElapsedMilliseconds.ToString(CultureInfo.InvariantCulture) +
                ",\"utc\":\"" + Escape(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)) + "\"}");
        }

        private void WriteWindowDiagnostics() {
            Rectangle bounds = Bounds;
            Rectangle primaryBounds = Screen.PrimaryScreen.Bounds;
            Rectangle workingArea = Screen.PrimaryScreen.WorkingArea;
            IntPtr foreground = NativeMethods.GetForegroundWindow();
            writer.WriteLine("{\"kind\":\"window_diagnostics\",\"formBounds\":" + RectJson(bounds) +
                ",\"primaryScreenBounds\":" + RectJson(primaryBounds) +
                ",\"primaryWorkingArea\":" + RectJson(workingArea) +
                ",\"formHandle\":\"0x" + Handle.ToInt64().ToString("X", CultureInfo.InvariantCulture) + "\"" +
                ",\"foregroundHandle\":\"0x" + foreground.ToInt64().ToString("X", CultureInfo.InvariantCulture) + "\"" +
                ",\"formIsForeground\":" + Bool(foreground == Handle) +
                ",\"topMost\":" + Bool(TopMost) + ",\"windowState\":\"" + WindowState.ToString() + "\"}");
        }

        public static bool EnableMousePointerMessages() { return NativeMethods.EnableMouseInPointer(true); }
        public static bool MousePointerMessagesEnabled() { return NativeMethods.IsMouseInPointerEnabled(); }

        private void WriteSummary() {
            if (finished) return;
            finished = true;
            durationTimer.Stop();
            string minPressureJson = pressureSampleCount > 0 ? minimumPressure.ToString(CultureInfo.InvariantCulture) : "null";
            string maxPressureJson = pressureSampleCount > 0 ? maximumPressure.ToString(CultureInfo.InvariantCulture) : "null";
            writer.WriteLine("{\"kind\":\"summary\",\"endedUtc\":\"" + Escape(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture)) +
                "\",\"elapsedMs\":" + clock.ElapsedMilliseconds.ToString(CultureInfo.InvariantCulture) +
                ",\"eventRecordsLogged\":" + eventRecordsLogged.ToString(CultureInfo.InvariantCulture) +
                ",\"penEventsLogged\":" + eventCount.ToString(CultureInfo.InvariantCulture) +
                ",\"penEventsObserved\":" + penEventCount.ToString(CultureInfo.InvariantCulture) +
                ",\"mouseMessagesObserved\":" + mouseMessageCount.ToString(CultureInfo.InvariantCulture) +
                ",\"mouseSourcePenMessages\":" + mouseSourcePenCount.ToString(CultureInfo.InvariantCulture) +
                ",\"legacyPenSignatureMessages\":" + legacyPenSignatureCount.ToString(CultureInfo.InvariantCulture) +
                ",\"legacyTouchSignatureMessages\":" + legacyTouchSignatureCount.ToString(CultureInfo.InvariantCulture) +
                ",\"mouseMoveCount\":" + Count(mouseCounts, "move").ToString(CultureInfo.InvariantCulture) +
                ",\"mouseLeftDownCount\":" + Count(mouseCounts, "left_down").ToString(CultureInfo.InvariantCulture) +
                ",\"mouseLeftUpCount\":" + Count(mouseCounts, "left_up").ToString(CultureInfo.InvariantCulture) +
                ",\"eventLimitReached\":" + Bool(limitReached) +
                ",\"downCount\":" + Count("down").ToString(CultureInfo.InvariantCulture) +
                ",\"updateCount\":" + Count("update").ToString(CultureInfo.InvariantCulture) +
                ",\"upCount\":" + Count("up").ToString(CultureInfo.InvariantCulture) +
                ",\"enterCount\":" + Count("enter").ToString(CultureInfo.InvariantCulture) +
                ",\"leaveCount\":" + Count("leave").ToString(CultureInfo.InvariantCulture) +
                ",\"pressureSamples\":" + pressureSampleCount.ToString(CultureInfo.InvariantCulture) +
                ",\"nonzeroPressureSamples\":" + nonzeroPressureCount.ToString(CultureInfo.InvariantCulture) +
                ",\"distinctPressureValues\":" + distinctPressures.Count.ToString(CultureInfo.InvariantCulture) +
                ",\"minPressure\":" + minPressureJson + ",\"maxPressure\":" + maxPressureJson +
                ",\"pressureNote\":\"These are Windows-reported values; physical pressure and application brush response require separate validation.\"}");
            writer.Flush();
            writer.Dispose();
        }

        private int Count(string name) { return Count(eventCounts, name); }
        private static int Count(Dictionary<string, int> counts, string name) { int count; return counts.TryGetValue(name, out count) ? count : 0; }
        private static string RectJson(Rectangle value) {
            return "{\"x\":" + value.X.ToString(CultureInfo.InvariantCulture) +
                ",\"y\":" + value.Y.ToString(CultureInfo.InvariantCulture) +
                ",\"width\":" + value.Width.ToString(CultureInfo.InvariantCulture) +
                ",\"height\":" + value.Height.ToString(CultureInfo.InvariantCulture) + "}";
        }
        private static string Bool(bool value) { return value ? "true" : "false"; }
        private static string Escape(string value) {
            if (value == null) return "";
            return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n").Replace("\t", "\\t");
        }
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies @('System.Windows.Forms.dll', 'System.Drawing.dll')
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
$mousePointerEnableSucceeded = $false
$mousePointerEnableError = 0
if ($EnableMouseInPointer) {
    $mousePointerEnableSucceeded = [WindowsPenInspector.PenCanvas]::EnableMousePointerMessages()
    if (-not $mousePointerEnableSucceeded) {
        $mousePointerEnableError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    }
}
$mousePointerEnabled = [WindowsPenInspector.PenCanvas]::MousePointerMessagesEnabled()
$form = [WindowsPenInspector.PenCanvas]::new($resolvedOutput, $DurationSeconds, [bool]$EnableMouseInPointer, $mousePointerEnableSucceeded, $mousePointerEnableError)
try {
    [Windows.Forms.Application]::Run($form)
} finally {
    if ($null -ne $form) { $form.Dispose() }
}
Write-Host ("Pen event log: {0}" -f $resolvedOutput)
