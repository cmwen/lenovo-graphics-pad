# Read-only Windows host HID descriptor inspection for the physical Lenovo device.
$ErrorActionPreference = 'Stop'

if (-not ('GraphicsPadHidProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class GraphicsPadHidProbe {
    const uint DIGCF_PRESENT = 0x2, DIGCF_DEVICEINTERFACE = 0x10;
    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2, OPEN_EXISTING = 3;
    static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA {
        public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved;
    }
    [StructLayout(LayoutKind.Sequential)] struct HIDD_ATTRIBUTES {
        public int Size; public ushort VendorID, ProductID, VersionNumber;
    }
    [StructLayout(LayoutKind.Sequential)] struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices;
        public ushort NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
    }
    [StructLayout(LayoutKind.Sequential)] struct HIDP_LINK_COLLECTION_NODE {
        public ushort LinkUsage, LinkUsagePage, Parent, NumberOfChildren, NextSibling, FirstChild;
        public uint CollectionFlags;
        public IntPtr UserContext;
    }

    [StructLayout(LayoutKind.Sequential)] struct HIDP_VALUE_CAPS {
        public ushort UsagePage;
        public byte ReportID, IsAlias;
        public ushort BitField, LinkCollection, LinkUsage, LinkUsagePage;
        public byte IsRange, IsStringRange, IsDesignatorRange, IsAbsolute, HasNull, Reserved;
        public ushort BitSize, ReportCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=5)] public ushort[] Reserved2;
        public uint UnitsExp, Units;
        public int LogicalMin, LogicalMax, PhysicalMin, PhysicalMax;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=8)] public ushort[] UsageUnion;
    }
    [DllImport("hid.dll")] static extern int HidP_GetValueCaps(int reportType, IntPtr caps, ref ushort length, IntPtr preparsed);

    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid hidGuid);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_GetAttributes(IntPtr h, ref HIDD_ATTRIBUTES a);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_GetPreparsedData(IntPtr h, out IntPtr data);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out HIDP_CAPS caps);
    [DllImport("hid.dll")] static extern int HidP_GetLinkCollectionNodes([Out] HIDP_LINK_COLLECTION_NODE[] nodes, ref uint count, IntPtr data);
    [DllImport("hid.dll", SetLastError=true)] static extern bool HidD_SetOutputReport(IntPtr h, byte[] report, int length);
    [DllImport("setupapi.dll", SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr hwnd, uint flags);
    [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid g, uint index, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr set, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, uint size, out uint required, IntPtr devInfo);
    [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(IntPtr h, byte[] buffer, uint count, out uint written, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);

    static Exception Win32(string operation) { return new Win32Exception(Marshal.GetLastWin32Error(), operation); }
    static string DetailPath(IntPtr set, ref SP_DEVICE_INTERFACE_DATA item) {
        uint needed;
        SetupDiGetDeviceInterfaceDetailW(set, ref item, IntPtr.Zero, 0, out needed, IntPtr.Zero);
        if (needed < 6) throw Win32("Query interface path size");
        IntPtr p = Marshal.AllocHGlobal((int)needed);
        try {
            Marshal.WriteInt32(p, IntPtr.Size == 8 ? 8 : 6);
            if (!SetupDiGetDeviceInterfaceDetailW(set, ref item, p, needed, out needed, IntPtr.Zero)) throw Win32("Read interface path");
            return Marshal.PtrToStringUni(IntPtr.Add(p, 4));
        } finally { Marshal.FreeHGlobal(p); }
    }
    public static void Run() {
        Guid guid; HidD_GetHidGuid(out guid);
        IntPtr set = SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (set == INVALID_HANDLE_VALUE) throw Win32("Enumerate HID interfaces");
        int matches = 0;
        try {
            for (uint i = 0; ; i++) {
                SP_DEVICE_INTERFACE_DATA item = new SP_DEVICE_INTERFACE_DATA(); item.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref item)) {
                    int error = Marshal.GetLastWin32Error(); if (error == 259) break;
                    throw new Win32Exception(error, "Enumerate HID interface");
                }
                string path = DetailPath(set, ref item);
                IntPtr h = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
                if (h == INVALID_HANDLE_VALUE) continue;
                try {
                    HIDD_ATTRIBUTES a = new HIDD_ATTRIBUTES(); a.Size = Marshal.SizeOf(typeof(HIDD_ATTRIBUTES));
                    if (!HidD_GetAttributes(h, ref a) || a.VendorID != 0x17EF || a.ProductID != 0x201C) continue;
                    matches++;
                    Console.WriteLine("MATCH VID={0:X4} PID={1:X4} Version={2:X4}", a.VendorID, a.ProductID, a.VersionNumber);
                    Console.WriteLine("Path: {0}", path);
                    IntPtr pp;
                    if (!HidD_GetPreparsedData(h, out pp)) { Console.WriteLine("Caps: unavailable ({0})", Win32("Get preparsed data").Message); continue; }
                    HIDP_CAPS caps;
                    try {
                        int status = HidP_GetCaps(pp, out caps);
                        if (status != 0x00110000) { Console.WriteLine("HidP_GetCaps NTSTATUS=0x{0:X8}", status); continue; }
                        Console.WriteLine("Interop: HIDP_CAPS size={0} (expected 64)", Marshal.SizeOf(typeof(HIDP_CAPS)));
                        IntPtr rawCaps = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(HIDP_CAPS)));
                        try {
                            Marshal.StructureToPtr(caps, rawCaps, false);
                            byte[] bytes = new byte[Marshal.SizeOf(typeof(HIDP_CAPS))]; Marshal.Copy(rawCaps, bytes, 0, bytes.Length);
                            Console.WriteLine("HIDP_CAPS bytes: {0}", BitConverter.ToString(bytes));
                        } finally { Marshal.FreeHGlobal(rawCaps); }
                        ushort valueCount = caps.NumberInputValueCaps;
                        int valueSize = Marshal.SizeOf(typeof(HIDP_VALUE_CAPS));
                        if (valueCount > 0 && valueCount < 64 && valueSize == 72) {
                            IntPtr values = Marshal.AllocHGlobal(valueCount * valueSize);
                            try {
                                int valueStatus = HidP_GetValueCaps(0, values, ref valueCount, pp);
                                if (valueStatus == 0x00110000) for (int v = 0; v < valueCount; v++) {
                                    HIDP_VALUE_CAPS value = (HIDP_VALUE_CAPS)Marshal.PtrToStructure(IntPtr.Add(values, v * valueSize), typeof(HIDP_VALUE_CAPS));
                                    Console.WriteLine("Value page={0:X4} usage={1:X4} report={2} bits={3} count={4} logical={5}..{6} physical={7}..{8} unit=0x{9:X} exponent=0x{10:X}",
                                        value.UsagePage, value.UsageUnion[0], value.ReportID, value.BitSize, value.ReportCount,
                                        value.LogicalMin, value.LogicalMax, value.PhysicalMin, value.PhysicalMax, value.Units, value.UnitsExp);
                                }
                            } finally { Marshal.FreeHGlobal(values); }
                        }
                        if (caps.NumberLinkCollectionNodes > 0) {
                            HIDP_LINK_COLLECTION_NODE[] nodes = new HIDP_LINK_COLLECTION_NODE[caps.NumberLinkCollectionNodes];
                            uint nodeCount = (uint)nodes.Length;
                            int nodeStatus = HidP_GetLinkCollectionNodes(nodes, ref nodeCount, pp);
                            if (nodeStatus == 0x00110000) {
                                HIDP_LINK_COLLECTION_NODE root = nodes[0];
                                Console.WriteLine("Collection root[0]: UsagePage=0x{0:X4} Usage=0x{1:X4} Children={2} FirstChild={3} Type={4} IsAlias={5}", root.LinkUsagePage, root.LinkUsage, root.NumberOfChildren, root.FirstChild, root.CollectionFlags & 0xff, ((root.CollectionFlags >> 8) & 1) != 0);
                            } else Console.WriteLine("HidP_GetLinkCollectionNodes NTSTATUS=0x{0:X8} count={1}", nodeStatus, nodeCount);
                        } else Console.WriteLine("Collection nodes: reported as zero; root unavailable");
                    } finally { HidD_FreePreparsedData(pp); }
                    Console.WriteLine("Caps: UsagePage=0x{0:X4} Usage=0x{1:X4} Input={2} Output={3} Feature={4}", caps.UsagePage, caps.Usage, caps.InputReportByteLength, caps.OutputReportByteLength, caps.FeatureReportByteLength);

                } finally { CloseHandle(h); }
            }
        } finally { SetupDiDestroyDeviceInfoList(set); }
        if (matches == 0) Console.WriteLine("No present HID interface matched VID 17EF / PID 201C.");
    }
}
'@
}

[GraphicsPadHidProbe]::Run()
