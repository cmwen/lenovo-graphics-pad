# Implementation validation — 2026-10-23

Implementation and review used isolated workspace run `R-20261023064849-2c09b74f`, with the Codex Micro repository read-only. Luna subagents handled the native input/protocol, Bluetooth adapter, Flutter controls, and bounded host utilities; parent reviewed and corrected integration and runtime issues.

## Automated checks

- Dart formatting, `flutter analyze`: passed, no issues.
- `flutter test`: all 7 widget/control tests passed. Coverage includes authoritative state gating, transport selection, persisted setting bounds, error propagation, concise diagnostics,320×568 portrait and853×533 landscape.
- `bash scripts/check-pen-protocol.sh`: passed. Independent Java descriptor parser checks report ID/length/flags/ranges, physical X/Y units and ranges, pressure scoping, eraser/hover/release reports, finite input handling, rotations, mirroring and centered active-area mapping.
- `flutter build apk --debug --no-pub`: passed with Kotlin and strict C JNI `-Wall -Wextra -Werror` compilation.
- Optional Astro website: `npm ci` and production build passed, four routes.
- `git diff --check` and `ws validate`: passed. Empty system registries produce the existing derived-topology warning.

## Device and host checks

Installed and launched on the actual rooted Lenovo TB-8505F / Android 10. Magisk's app-specific superuser entry was enabled through its UI after confirming shell root alone did not authorize the app. Native input rendered real local strokes from finite Android touchscreen injections without a crash. Device capability inventory showed no active stylus source; touch pressure is explicitly binary.

USB was explicitly started from the app. Windows confirmed external pen UsagePage000D/Usage0001, Input 8 / Output 0 / Feature 0 and ready+external-pen system capability flags. ADB stayed available alongside HID. The app recorded 58 successful report writes and 0 drops on the initial pipeline test; the physical-range descriptor was subsequently built, installed and exercised with additional strokes.

Manual USB stop and app force-stop both restored original ADB-only configuration, controller binding and removed FunctionFS/recovery state. Two Windows ADB servers competed after re-enumeration; the unused 5037 server was stopped and subsequent tests used 5038. This was a test-environment visibility issue, not a failed tablet restore.

Classic Bluetooth callback-confirmed HID registration succeeded on the tablet; Android's 120-second discoverability dialog was exercised and allowed. Windows Classic inquiry found the tablet. Authentication reached Android bonding but did not complete without confirmed prompts (Windows1244); no new bond was established. Host pairing/drawing results are tracked in HARDWARE_ACCEPTANCE.md. Windows host utilities were runtime-checked; the pen inspector logs only its own window and separates true pen messages from mouse events.

The Windows GUI test ran in an RDP session, separate from the physical console, and did not capture native pen events. A local-console drawing-application pass, Mac pairing/application behavior, physical pen pressure/buttons/hover and measured input-to-host latency remain unverified. Do not equate descriptor recognition or injected binary contact with those results.

Final APK SHA-256: `242260c35c2237855f40d7e0f42d9c7e72c22ff5a25d5dfb94f0aff6eaefa19a`. Final host value-cap inspection confirmed X/Y physical units, independent physical maxima1013/841 and unscoped pressure0..4095. A final native stroke and manual restoration were rechecked after installing this APK.
