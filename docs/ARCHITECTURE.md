# Pen pipeline and transport design

## Pipeline

Android input → calibrated pen sample → bounded report encoder → selected transport → host event inspector → target drawing app.

Flutter provides controls and settings. The Android `PadSurface` captures `MotionEvent` history, tool source, hover, barrel/eraser and device motion ranges and sends reports directly to the selected native transport. UI sample events are throttled independently of HID sends. Preserve ordered tip-up/in-range transitions and send an all-up report before stopping. Define orientation, active area, aspect ratio and host-display mapping explicitly. Finger input must be labelled as touch; do not synthesize advertised physical pressure sensitivity.

The starter encoder defines report ID 1 and a seven-byte body: flags (tip bit0, in-range bit1, barrel bit2, invert bit3, eraser bit4), X uint16 little-endian, Y uint16 little-endian, pressure uint16 little-endian. X/Y normalize to 0..32767, pressure to 0..4095. The native `PenProtocol` owns the complete report descriptor; independent Java checks parse its input fields and compare the wire contract. USB input prepends the ID; Classic Android `sendReport` supplies the ID separately. Descriptor flags, padding, ranges and byte lengths match the encoder. At session start, physical axis ranges are derived from the actual pad view size and Android-reported xdpi/ydpi, active-area fractions and rotation. The descriptor uses SI linear centimeters with exponent -2 (tenths of a millimeter). These are firmware-reported dimensions, not a ruler calibration. Restart the transport after mapping changes so the host receives updated geometry.

## Bluetooth

The Bluetooth adapter uses Android [BluetoothHidDevice](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice), API 28+: standard external pen/digitizer SDP report map, callback-confirmed registration and connection, explicit discoverability/pairing, Android-version-specific runtime permissions, and bounded report sends. Registration depends on foreground state and only one HID app can register. Never mark connected from `registerApp` returning true.

The prior app uses BLE HOGP, not the same transport. Port its encrypted GATT sequencing only if BLE is selected after a host test; do not implement two Bluetooth stacks without evidence. Pairing, subscription, report delivery and native pen events are separate milestones.

## USB

Rooted USB device/gadget mode is required; Android USB host APIs do not turn the tablet into a pen peripheral. Use the existing FunctionFS investigation, not configfs `hid.usb0` on this stock Lenovo kernel. FunctionFS registers descriptors and strings through ep0 and creates endpoint files: [Linux FunctionFS documentation](https://www.kernel.org/doc/html/latest/usb/functionfs.html).

Root helper requirements: exclusive controller ownership, atomic private snapshot, preserve ADB, unique app-owned function, bounded startup/I/O, explicit teardown, lifecycle all-up, restore on normal stop and helper EOF, recovery on reopening. Gadget binding must occur only after endpoints are ready. Test unexpected cable and process termination separately. USB activation is explicit and temporary. This port accepts an original ADB-only configuration and refuses all other linked functions, including other apps' FunctionFS sessions. It retains Lenovo's physical VID/PID, changes bcdDevice for the new configuration, and restores the snapshot on stop. No Wacom or Micro identity is copied.

## Host pen semantics

Use Digitizers usage page 0x0D with an external Pen application collection. Validate whether hosts require a different collection or device-specific treatment; integrated-display pen rules must not automatically be applied to an external pad. Microsoft documents [digitizer usages](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/supporting-usages-in-digitizer-report-descriptors) and [integrated pen collections](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/required-hid-top-level-collections). These are references, not a compatibility guarantee for our candidate descriptor.

Apple documents [stylus HID input handling](https://developer.apple.com/documentation/hiddriverkit/handling-stylus-input-from-a-human-interface-device) and [tablet pressure events](https://developer.apple.com/documentation/coregraphics/cgeventfield/tableteventpointpressure). Those APIs do not establish automatic driverless graphics-pad support for arbitrary descriptors. If macOS needs a host driver or companion component, record that as a product tradeoff and test it explicitly.

Android [MotionEvent](https://developer.android.com/reference/android/view/MotionEvent) pressure is device-dependent and may be approximate. Normalize using observed device ranges only after testing; distinguish diagnostic values, binary contact and verified continuous pen pressure.
