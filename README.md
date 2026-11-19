# Samsung PCB Programmer

Independent Android app project for Samsung refrigerator inverter PCB service research.

## Download APK
Open the [GitHub Actions builds](https://github.com/im-amane/Samsung-PCB-Programmer/actions/workflows/android.yml). Open the latest successful run and download **samsung-pcb-programmer-debug** under Artifacts.

## Included in this build
- No third-party account, activation, or license-verification flow
- PCB profile selector for the listed DA41 board variants
- USB OTG serial-device discovery and connection
- Firmware file import, SHA-256 fingerprint, and basic Motorola S-record checksum checks
- Static-analysis findings from the supplied APK displayed in the dashboard
- Research notes covering firmware asset names, engine symbols, MCU clues, and unverified bootloader workflow (`docs/REVERSE_ENGINEERING_NOTES.md`)

## Not yet implemented
This independent app does not yet perform MCU erase, flash write, target verification, or reboot. Static inspection of the supplied APK revealed engine/transport symbols and candidate MCU/boot-mode clues, but not yet a verified packet-level protocol. See [reverse-engineering notes](docs/REVERSE_ENGINEERING_NOTES.md). Those operations remain disabled until the exact PCB revision, connector pinout, electrical levels, bootloader protocol, and firmware compatibility are confirmed and tested on the actual hardware. The original APK's verification mechanism has not been modified or bypassed.

## Build locally
```bash
flutter pub get
flutter run
flutter build apk --debug
```

## Safety
Disconnect the refrigerator PCB from mains power before any inspection. Inverter capacitors can retain dangerous voltage. Never connect or flash a live board.
