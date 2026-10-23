# Implementation and acceptance

## Implemented

- Public Android repository, template CI/release/signing and agent workflows.
- Native Android input surface and direct HID report pipeline, single-pointer capture, history processing, contact cancellation, hover, barrel/eraser and bounded local ink.
- Standard external-pen descriptor with reportID1, X/Y, pressure and pen flags; physical geometry derived from Android-reported active pad dimensions.
- Rooted userspace FunctionFS USB with exclusive ownership/refusal, ADB preservation, private snapshot, manual restore, EOF cleanup and reopen recovery.
- Classic Bluetooth HID registration, Android discoverability, paired-host selection, bounded sends, stale-peer protection and neutral release/disconnect.
- Rotation, mirrored X, centered active area, pressure mode/curve, finger-input and stylus button/eraser settings; persistent preferences and readable diagnostics.
- Protocol/mapping tests, Flutter control tests, Android APK and optional site builds.
- Pinned Codex Micro attribution/reuse record and Windows descriptor/event inspection tools.

## Remaining hardware acceptance

- [ ] Local Windows console: native pen events and a named art application over USB and Bluetooth.
- [ ] Mac: pairing/enumeration, native tablet events and a named drawing application over both transports.
- [ ] Real stylus hardware: pressure/hover/barrel/eraser only where the source device supports them. The tested built-in TB-8505F touchscreen has no active stylus source.
- [ ] Measure median/p95 latency and dropped reports using a stated method on both hosts.
- [ ] Physical cable-pull/reconnect and long sessions on the owner's host/hub configuration.
- [ ] Signed release APK after private release-signing configuration and host acceptance.

Device results and exact limitations are in HARDWARE_ACCEPTANCE.md. Do not restart the failed Lenovo configfs HID or USB audio investigation. Read CODEX_MICRO_REUSE.md before future Codex Monitor transport work.
