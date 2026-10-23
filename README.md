# Lenovo Graphics Pad

Use a rooted Lenovo Android tablet as a standard external pen HID device over USB or Bluetooth for Windows 11 and macOS.

The Android app includes native low-latency drawing input, USB FunctionFS HID with ADB recovery, Classic Bluetooth HID pairing, rotation and active-area mapping, pressure curve controls, stylus barrel/eraser support, optional finger input, and input-device diagnostics. Both transports use the same standard Digitizers-page report descriptor and pen encoder. No host-side network bridge is required.

**Hardware limit:** the tested Lenovo TB-8505F exposes touchscreen input, with no active stylus source. Finger input has binary contact pressure. Software cannot create a pressure-sensitive digitizer. Hover, continuous pressure and pen buttons work only when Android reports them from compatible hardware. Windows and macOS application compatibility must be checked separately; see [hardware results](docs/HARDWARE_ACCEPTANCE.md).

## Start drawing

1. Install a debug APK or build below, then open Graphics Pad. Local ink is available without a host.
2. **USB:** leave Android USB debugging enabled, choose USB, and tap Start. Grant **Graphics Pad** root in Magisk (shell root alone is insufficient). This temporarily replaces an ADB-only gadget with pen HID + ADB. Stop any Codex Micro USB session first. A data cable is required.
3. **Bluetooth:** stop USB and wait for restoration, choose Bluetooth, tap Start, then Make discoverable. Accept Android's pairing dialogs from Windows Bluetooth settings or macOS System Settings. Select a paired computer and connect if the host does not connect automatically. This uses Classic Bluetooth HID, not BLE. Pair using the tablet's existing Android Bluetooth name (change it in Android settings if desired). BLE-only bonds from Codex Micro are not Classic pen host connections.
4. Keep the app visible. Draw on the white pad. Open Settings for rotation, centered active area, pressure mode/curve, horizontal mirroring and input controls. Mapping changes release any held contact first.
5. Tap Stop before changing transport. **Restore Android USB / ADB** recovers an interrupted USB session. Reopening also attempts recovery when its private marker indicates it is needed. Sessions never restart automatically.

For multi-display mapping, use the host's tablet mapping tools where available; the app sends normalized absolute coordinates. Active-area width/height and rotation can compensate for orientation and aspect ratio. The app does not enumerate host displays or install a Wacom driver.

## Build and check

Flutter 3.38.7, Java 17, Android SDK/NDK and CMake 3.22.1. Android 9/API 28 or later; USB requires root plus the Lenovo configfs/FunctionFS layout.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
bash scripts/check-pen-protocol.sh
flutter build apk --debug
flutter run
```

Application ID: `com.cmwen.lenovo_graphics_pad`. Release keys remain private; see [SIGNING.md](SIGNING.md). Created from [min-android-app-template](https://github.com/cmwen/min-android-app-template), retaining debug CI, signing/release workflows and agent templates.

## Verification and implementation notes

[Windows HID descriptor inspection](scripts/inspect-windows-hid.ps1) checks the actual host-visible collection and report length. [Windows pen inspector](scripts/windows-pen-inspector.ps1) opens a short-lived canvas and records native pen events delivered to that window. Run it with Windows PowerShell `-STA`. Logs contain event coordinates; keep them private unless intentionally sharing a test result.

Read [architecture](docs/ARCHITECTURE.md), [Codex Micro reuse](docs/CODEX_MICRO_REUSE.md), [validation](docs/VALIDATION.md) and [remaining hardware checks](docs/ROADMAP.md). Existing Lenovo kernel failures and the proven FunctionFS workaround are preserved for future Codex Monitor work. Native transport attribution and the pinned upstream version are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
