# Hardware acceptance record

All cells start **not tested**. Do not turn a successful build, HID enumeration or Micro vendor discovery into a graphics-pad pass.

| Host | USB pen events | Bluetooth pen events | Continuous pressure | Drawing app |
| --- | --- | --- | --- | --- |
| Windows 11 (record build) | Not tested | Not tested | Not tested | Windows Ink target + named art app: not tested |
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
