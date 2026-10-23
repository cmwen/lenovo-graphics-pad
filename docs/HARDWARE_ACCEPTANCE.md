# Hardware acceptance record

Device checks on 2026-10-23 used Lenovo TB-8505F, Android 10, with Magisk app root. Touch devices `mtk-tpd` and `fts_ts` expose touchscreen sources and no active stylus source. Continuous pressure, hover and physical pen buttons are unavailable on the tested built-in input. Do not turn HID enumeration into a drawing-application pass.

| Host | USB pen events | Bluetooth pen events | Continuous pressure | Drawing app |
| --- | --- | --- | --- | --- |
| Windows 11 build 26300 | External pen descriptor and USB writes verified; local-console pen events pending | Tablet HID registration, discoverability and Windows Classic inquiry verified; authentication not completed | Touch contact only (binary); no built-in active stylus | Test window was in RDP session 2, with console session 1 separate; native drawing-app behavior not verified |
| macOS (record version/model) | Not tested | Not tested | Not tested | Native drawing app + named art app: not tested |

For each transport/host combination record app commit, APK, tablet model/ROM/kernel, pen model, descriptor bytes/hash, firmware/API support, connection type (Classic/BLE), cable/hub, host OS and art app versions.

1. Inspect Android input devices and MotionEvent source/tool/motion ranges read-only. Confirm active stylus, hover and continuous pressure if present; constant 0/1 or capacitive estimates do not prove pen pressure.
2. Inspect actual USB descriptor or Bluetooth SDP/GATT map on the host. Require digitizer/pen collection, intended ranges and report lengths; reject the Lenovo empty/hardcoded HID descriptor.
3. Verify native host pen/tablet events, not only mouse movement. Map four corners and center, orientation, aspect ratio and selected display.
4. Exercise tip down/move/up, hover/in-range, barrel and eraser when supported, multi-touch rejection, focus loss, cancellation and disconnect. Verify no stuck contact.
5. Inspect actual host pressure samples and application brush response. Report binary contact separately from continuous pressure. Never manufacture a physical-pressure pass.
6. Measure median and p95 input-to-host latency with methodology and sample count; record dropped reports. Test slow strokes and rapid direction changes.
7. Test lock/sleep, rotation, app backgrounding, reconnect and switching host. Check independent USB and Bluetooth results.
8. USB: verify ADB before and after, normal stop, app force-stop, helper termination, cable pull and reopen recovery. Document any remaining recovery limitation. Refuse concurrent ownership by Codex Micro.

An acceptable initial host result is absolute position + clean tip contact, clearly labelled if pressure is unavailable. The full graphics-pad goal requires the requested art application's pen behavior on each host. Wacom branding, protocol spoofing or an unverified VID/PID must not substitute for standard HID evidence.

## USB device evidence

- Physical Lenovo identity retained: VID17EF/PID201C; pen mode bcdDevice0200, ADB interface0 plus HID interface1.
- Windows HidP_GetCaps: usage page000D/usage0001; input8 bytes, output0, feature0; HID-compliant digitizer with no device problem. SM_DIGITIZER=136 (ready + external pen).
- Tablet app showed USB HID+ADB enabled and connected. Finite Android touchscreen swipe/tap injection produced local ink and58 completed USB writes with0 dropped reports on the first descriptor. Repeated strokes also exercised the descriptor with physical axis ranges. These are synthetic source events testing the pipeline, not proof of a real pressure stylus.
- App force-stop restored sys.usb.config=adb, bound controller musb-hdrc, original ADB-only f1 link, and removed FunctionFS mount/function/state.json. Two Windows ADB servers initially obscured the result; testing then retained only port5038.
- Windows PowerShell ran in RDP session2 on a542×1148 remote display while the physical console was session1. The visible WinForms inspector recorded no native pen events in that remote session. Local-console and art-application tests remain required; do not claim a drawing-app pass.
- Private screenshots and event-inspector logs are workspace artifacts, not committed device serials or user event coordinates.

## Bluetooth evidence

The native Classic HID profile registered successfully on the tablet and remained ready through Android's discoverability dialog. Windows' MediaTek Bluetooth adapter discovered the tablet with the same physical adapter address using a bounded Win32 BR/EDR inquiry. The tablet retained its pre-existing Android system Bluetooth name. An explicit authentication attempt reached Android BOND_BONDING, then failed after unconfirmed authentication (Windows1244 / Android authentication failure). No new host bond was established. Complete the normal pairing prompts on both devices from the local Windows desktop or Mac; do not count discovery as a paired-pen pass. BLE-only bonds are excluded from the Classic host selector.

Final APK host inspection additionally verified per-axis caps: X/Y logical0..32767, X physical0..1013 and Y0..841 in0.1mm units (SI centimeter unit11, exponentE=-2), pressure logical0..4095 with no inherited axis physical unit/range. Dimensions101.3×84.1mm derive from Android-reported pixel density and the active landscape view, not an external ruler measurement. Final native mapping stroke and manual stop were rechecked.
