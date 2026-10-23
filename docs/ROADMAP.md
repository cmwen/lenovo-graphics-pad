# Implementation milestones

- [x] Create public app repository from the Android template and register it in the workspace.
- [x] Local input preview, pen payload encoder and automated foundation tests.
- [x] Preserve Codex Micro Lenovo USB findings and transport reuse map.
- [ ] Capture actual tablet input capabilities. Exit: model/ROM/pen and source/pressure/hover evidence in hardware record.
- [ ] Define and inspect a complete external-pen HID descriptor. Exit: descriptor parser and independent host dumps match report tests, ranges and measured dimensions.
- [ ] Bluetooth native adapter. Exit: Win11 and Mac pairing plus actual pen events; foreground loss sends release and unregisters cleanly.
- [ ] Extract/port the proven FunctionFS backend with attribution and shared ownership. Exit: same descriptor/report contract as Bluetooth, ADB survives and recovery tests pass.
- [ ] Host application matrix. Exit: absolute mapping, pressure status, buttons, latency, reconnection and named drawing app results for both operating systems and both transports.
- [ ] Publish a tested APK and user setup/recovery instructions. Keep release signing private.

Do not restart configfs HID or USB audio investigation on the known Lenovo stock kernel. Read CODEX_MICRO_REUSE.md first. Do not promise pressure from a touchscreen that lacks a pressure-capable pen digitizer.
