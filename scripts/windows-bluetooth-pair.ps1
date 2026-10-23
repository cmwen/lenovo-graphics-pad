<#
.SYNOPSIS
  Read-only bounded Windows Classic Bluetooth discovery, with explicit pairing by address.
.DESCRIPTION
  Default mode performs a Bluetooth BR/EDR inquiry (15 seconds maximum) across all local
  radios and prints Name, Address, Id, and IsPaired. Pairing is attempted only when
  -PairAddress is supplied. That path invokes the standard Windows authentication wizard;
  this script never supplies a PIN or automatically accepts a pairing prompt. It has no
  unpair operation and does not change radio, driver, or host settings.
.EXAMPLE
  powershell.exe -STA -ExecutionPolicy Bypass -File .\scripts\windows-bluetooth-pair.ps1
.EXAMPLE
  powershell.exe -STA -ExecutionPolicy Bypass -File .\scripts\windows-bluetooth-pair.ps1 -PairAddress 'AA:BB:CC:DD:EE:FF'
.NOTES
  Uses BluetoothFindFirstDevice / BluetoothFindNextDevice from the Win32 Bluetooth APIs.
  BluetoothFindFirstDevice searches Classic Bluetooth, not Bluetooth LE.
  Microsoft references:
  https://learn.microsoft.com/en-us/windows/win32/api/bluetoothapis/ns-bluetoothapis-bluetooth_device_search_params
  https://learn.microsoft.com/en-us/windows/win32/api/bluetoothapis/nf-bluetoothapis-bluetoothfindfirstdevice
  https://learn.microsoft.com/en-us/windows/win32/api/bluetoothapis/nf-bluetoothapis-bluetoothauthenticatedeviceex
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 15)]
    [int] $InquirySeconds = 15,
    [string] $Name,
    [string] $PairAddress
)

$ErrorActionPreference = 'Stop'
if ($PairAddress -and $PairAddress -notmatch '(?i)^[0-9a-f]{2}(:[0-9a-f]{2}){5}$') {
    throw 'PairAddress must be a Bluetooth address in XX:XX:XX:XX:XX:XX form.'
}

$source = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class WindowsBluetoothClassic {
    [StructLayout(LayoutKind.Sequential)]
    private struct SearchParams {
        public uint Size;
        [MarshalAs(UnmanagedType.Bool)] public bool ReturnAuthenticated;
        [MarshalAs(UnmanagedType.Bool)] public bool ReturnRemembered;
        [MarshalAs(UnmanagedType.Bool)] public bool ReturnUnknown;
        [MarshalAs(UnmanagedType.Bool)] public bool ReturnConnected;
        [MarshalAs(UnmanagedType.Bool)] public bool IssueInquiry;
        public byte TimeoutMultiplier;
        public IntPtr Radio;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeSystemTime {
        public ushort Year;
        public ushort Month;
        public ushort DayOfWeek;
        public ushort Day;
        public ushort Hour;
        public ushort Minute;
        public ushort Second;
        public ushort Milliseconds;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct DeviceInfo {
        public uint Size;
        public ulong Address;
        public uint ClassOfDevice;
        [MarshalAs(UnmanagedType.Bool)] public bool Connected;
        [MarshalAs(UnmanagedType.Bool)] public bool Remembered;
        [MarshalAs(UnmanagedType.Bool)] public bool Authenticated;
        public NativeSystemTime LastSeen;
        public NativeSystemTime LastUsed;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)] public string Name;
    }

    public sealed class DeviceRecord {
        public string Name { get; set; }
        public string Address { get; set; }
        public string Id { get; set; }
        public bool IsPaired { get; set; }
        public bool IsConnected { get; set; }
        public bool IsRemembered { get; set; }
        internal DeviceInfo NativeInfo;
    }

    [DllImport("bthprops.cpl", SetLastError = true)]
    private static extern IntPtr BluetoothFindFirstDevice(ref SearchParams search, ref DeviceInfo info);

    [DllImport("bthprops.cpl", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothFindNextDevice(IntPtr findHandle, ref DeviceInfo info);

    [DllImport("bthprops.cpl", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothFindDeviceClose(IntPtr findHandle);

    [DllImport("bthprops.cpl", SetLastError = true)]
    private static extern uint BluetoothAuthenticateDeviceEx(
        IntPtr parentWindow,
        IntPtr radio,
        ref DeviceInfo info,
        IntPtr oobData,
        uint authenticationRequirements);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetConsoleWindow();

    public static int LastDiscoveryError { get; private set; }
    public static int InquiryTimeoutSeconds { get; private set; }

    public static List<DeviceRecord> Discover(int requestedSeconds) {
        // cTimeoutMultiplier uses 1.28-second units and is capped here to 11 units
        // (14.08 seconds), keeping the radio inquiry below the requested 15-second max.
        int multiplier = Math.Max(1, Math.Min(11, (int)Math.Floor(requestedSeconds / 1.28)));
        InquiryTimeoutSeconds = (int)Math.Ceiling(multiplier * 1.28);
        SearchParams search = new SearchParams();
        search.Size = (uint)Marshal.SizeOf(typeof(SearchParams));
        search.ReturnAuthenticated = true;
        search.ReturnRemembered = true;
        search.ReturnUnknown = true;
        search.ReturnConnected = true;
        search.IssueInquiry = true;
        search.TimeoutMultiplier = (byte)multiplier;
        search.Radio = IntPtr.Zero; // NULL searches all local Bluetooth radios.

        DeviceInfo info = NewDeviceInfo();
        IntPtr findHandle = BluetoothFindFirstDevice(ref search, ref info);
        LastDiscoveryError = findHandle == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
        List<DeviceRecord> devices = new List<DeviceRecord>();
        if (findHandle == IntPtr.Zero) return devices;

        try {
            do {
                devices.Add(ToRecord(info));
                info = NewDeviceInfo();
            } while (BluetoothFindNextDevice(findHandle, ref info));
            int enumerationError = Marshal.GetLastWin32Error();
            LastDiscoveryError = enumerationError == 259 ? 0 : enumerationError;
        } finally {
            BluetoothFindDeviceClose(findHandle);
        }
        return devices;
    }

    public static uint PairWithWindowsWizard(DeviceRecord record) {
        if (record == null) throw new ArgumentNullException("record");
        DeviceInfo info = record.NativeInfo;
        info.Size = (uint)Marshal.SizeOf(typeof(DeviceInfo));
        // Null OOB data explicitly requests the Windows authentication UI. No callback
        // is registered here, so the script cannot auto-accept a code or comparison.
        const uint MitmProtectionNotRequired = 0;
        return BluetoothAuthenticateDeviceEx(GetConsoleWindow(), IntPtr.Zero, ref info,
            IntPtr.Zero, MitmProtectionNotRequired);
    }

    private static DeviceInfo NewDeviceInfo() {
        DeviceInfo info = new DeviceInfo();
        info.Size = (uint)Marshal.SizeOf(typeof(DeviceInfo));
        info.Name = String.Empty;
        return info;
    }

    private static DeviceRecord ToRecord(DeviceInfo info) {
        string address = FormatAddress(info.Address);
        string name = String.IsNullOrWhiteSpace(info.Name) ? "(unknown name)" : info.Name.TrimEnd('\0');
        return new DeviceRecord {
            Name = name,
            Address = address,
            Id = "BTH:" + address,
            IsPaired = info.Authenticated,
            IsConnected = info.Connected,
            IsRemembered = info.Remembered,
            NativeInfo = info
        };
    }

    private static string FormatAddress(ulong address) {
        return String.Format(System.Globalization.CultureInfo.InvariantCulture,
            "{0:X2}:{1:X2}:{2:X2}:{3:X2}:{4:X2}:{5:X2}",
            (address >> 40) & 0xFF, (address >> 32) & 0xFF, (address >> 24) & 0xFF,
            (address >> 16) & 0xFF, (address >> 8) & 0xFF, address & 0xFF);
    }
}
'@

Add-Type -TypeDefinition $source
$devices = @([WindowsBluetoothClassic]::Discover($InquirySeconds))
$nativeError = [WindowsBluetoothClassic]::LastDiscoveryError
$timeout = [WindowsBluetoothClassic]::InquiryTimeoutSeconds
Write-Output ("Classic Bluetooth inquiry completed (radio timeout up to {0}s; Win32 status {1})." -f $timeout, $nativeError)

if ($Name) {
    $devices = @($devices | Where-Object { $_.Name -like "*$Name*" })
}
if ($devices.Count -eq 0) {
    Write-Output 'No matching Classic Bluetooth devices were found.'
} else {
    $devices | Select-Object Name, Address, Id, IsPaired | Format-Table -AutoSize | Out-Host
}

if (-not $PairAddress) {
    return
}

$targetAddress = ($PairAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
$matches = @($devices | Where-Object { ($_.Address -replace '[^0-9A-Fa-f]', '').ToUpperInvariant() -eq $targetAddress })
if ($matches.Count -ne 1) {
    throw "Expected one discovered device at address $PairAddress; found $($matches.Count). Discovery results above are read-only."
}
$target = $matches[0]
if ($target.IsPaired) {
    Write-Output "Device '$($target.Name)' ($PairAddress) is already paired; no pairing change was made."
    return
}

Write-Output "Requesting the Windows Bluetooth authentication wizard for '$($target.Name)' at $PairAddress. Confirm any requested action in Windows; this script does not supply a PIN or accept a prompt."
$pairingStatus = [WindowsBluetoothClassic]::PairWithWindowsWizard($target)
if ($pairingStatus -eq 0) {
    Write-Output 'Windows authentication wizard reported success.'
} else {
    throw ([ComponentModel.Win32Exception]::new([int]$pairingStatus, 'Bluetooth pairing did not complete. Confirm both Android and Windows prompts from the local desktop.'))
}
