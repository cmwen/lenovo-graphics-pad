# Lenovo Graphics Pad

Turn a rooted Lenovo Android tablet into an external graphics pad for Windows 11 and macOS over Bluetooth HID or USB HID.

**Status: foundation and feasibility prototype.** The app currently captures local input and previews pen reports. Bluetooth pairing, USB gadget activation, host pen events and pressure support are not implemented or verified in this repository. Selecting a transport does not connect a host. This is not yet a replacement for a Wacom tablet.

Created from [min-android-app-template](https://github.com/cmwen/min-android-app-template): Flutter Android project, automated debug builds, signing/release workflows, agent instructions, issue/PR templates and optional website starter.

## Run

Use Flutter 3.38.7 and Java 17 with an Android SDK:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

Application ID: `com.cmwen.lenovo_graphics_pad`. Release signing remains private; see [SIGNING.md](SIGNING.md). Do not copy Codex Micro signing keys, identifiers or vendor identities.

## Hardware and compatibility

The prior Codex Micro investigation used a rooted Lenovo Tab M8 TB-8505F running Android 10. The precise Lenovo model and pen hardware must be recorded before claiming pressure sensitivity. Touch pressure values do not establish an active stylus digitizer. Finger input remains useful for basic position and contact testing.

The product target is standard pen/digitizer HID that the host treats as a graphics pad. A connected HID device or moving mouse pointer alone does not meet this target. macOS and individual art applications require independent pen-event and pressure tests.

## Build from existing evidence

Start with [the Codex Micro reuse record](docs/CODEX_MICRO_REUSE.md), then [the transport architecture](docs/ARCHITECTURE.md) and [hardware acceptance checklist](docs/HARDWARE_ACCEPTANCE.md). These preserve the existing Lenovo USB findings instead of rediscovering them.

Implementation order and concrete exit criteria are in [ROADMAP.md](docs/ROADMAP.md). Luna subagents handled initial source research and the bounded app scaffold; changes were reviewed in an isolated workspace run.
