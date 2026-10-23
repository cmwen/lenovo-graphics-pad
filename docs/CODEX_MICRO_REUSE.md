# Codex Micro evidence and reuse boundary

Recorded 2026-10-23. Read this before probing Lenovo USB or Bluetooth.

Canonical source: [codex-micro-tablet](https://github.com/cmwen/codex-micro-tablet), revision `d2a3cf0eb56798f931afa9088fc710ca73ee17f7`. Its [hardware log](https://github.com/cmwen/codex-micro-tablet/blob/d2a3cf0eb56798f931afa9088fc710ca73ee17f7/docs/CODEX_MICRO_TABLET.md) is the evidence record, especially “FunctionFS HID correction”. Do not repeat the failed configfs-only experiment on the same stock build.

## Already established on TB-8505F / Android 10

- Android HID Device profile exists; rooted shell and app root authorization are separate.
- BLE HOGP vendor HID was confirmed by the owner. This is BLE, distinct from Classic Bluetooth HID Device API.
- Configfs HID attributes are writable but ignored by this Lenovo kernel. Windows saw Usage Page 0001 / Usage 0000 with zero report lengths despite the supplied descriptor. `/dev/hidg0` and successful enumeration alone are false positives.
- Lenovo GPL `f_hid.c` uses `#if 0 /* skip get data from userspace */` in `hidg_alloc`: [kernel source](https://github.com/T4rp/Lenovo-TB-8505FS-Kernel/blob/master/drivers/usb/gadget/function/f_hid.c).
- Userspace FunctionFS HID solved custom descriptor delivery. Windows confirmed vendor usage FF00/1 and 64-byte input/output/feature reports; control and interrupt OUT worked. The owner confirmed Micro discovery and working controls on Mac through a USB hub.
- Endpoint I/O required Linux AIO. Synchronous FunctionFS I/O can block despite O_NONBLOCK and endpoint poll was unavailable on this kernel.
- Recovery restored the original ADB gadget after manual stop and app force-stop. Helper EOF cleanup is best effort, not protection against every root-process kill or crash.
- USB audio failed and is outside this project.

These observations prove transport plumbing for the Micro vendor protocol. They do **not** prove pen registration, pressure, Windows Ink, macOS tablet events, or art app compatibility.

## Reuse plan

Review these files at the pinned revision before implementing any new driver:

| Existing component | Reusable responsibility | Required graphics-pad change |
| --- | --- | --- |
| `android/app/src/main/cpp/usb_functionfs_hid.c` | ep0 requests, FunctionFS descriptors, AIO lifecycle | Parameterize report map, report sizes and interface identity; remove Micro protocol assumptions |
| `android/app/src/main/kotlin/com/cmwen/codex_micro_tablet/UsbFunctionFs.kt` | JNI lifecycle | Separate library ownership and package binding |
| `UsbRootMain.kt` in same directory | exclusive session, snapshot, ADB preservation, restore | Use unique session/function/state names; serialize gadget ownership across apps |
| `UsbHidTransport.kt` | app/native boundary | Carry pen reports rather than vendor commands |
| `BleHidPeripheral.kt` | GATT sequencing, encrypted report access, disconnect cleanup | Replace report map and report references; verify pen interoperability |
| `MicroWire.java` | framing reference only | Do not reuse vendor JSON/report6 framing for pen input |

Do not blindly copy the Micro VID/PID, authentication, app keys, report6 identity, audio code or dashboard. Review license and attribution before copying native source. Begin by extracting a transport interface with explicit descriptors and lengths; keep Micro's caller behavior and regression tests unchanged. A shared versioned library is preferable once both clients establish a stable API. Until then use a pinned, attributed port and record divergence; do not create an untracked second driver.

One USB gadget controller and one Classic HID registration cannot be assumed available to both apps concurrently. Refuse an existing owner and provide a user-driven handoff. Never unlink another app's active gadget function.

Future Codex Monitor work should link this record and the pinned source hardware log. This repo starts with no root side effects; implementation must preserve temporary properties, ADB access, explicit start/stop and recovery. No boot daemon, SELinux changes, kernel flashing or persistent USB properties are part of the current design.
