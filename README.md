# Samsung PCB Programmer

Independent Android app project for Samsung refrigerator inverter PCB service research.

## Download APK
Open the [GitHub Actions builds](https://github.com/im-amane/Samsung-PCB-Programmer/actions/workflows/android.yml). Open the latest successful run and download **samsung-pcb-programmer-debug** under Artifacts.

## Included in this build
- No third-party account, activation, or license-verification flow in this independent app
- PCB profile selector for the currently documented DA41 variants
- USB OTG serial-device discovery and connection
- Firmware file import, SHA-256 fingerprint, and basic Motorola S-record checksum checks
- Static-analysis findings from the supplied Samsung Swap APK
- Detailed APK findings and exact bundled firmware hashes in [docs/SAMSUNG_SWAP_APK_ANALYSIS.md](docs/SAMSUNG_SWAP_APK_ANALYSIS.md)
- Existing protocol research notes in [docs/REVERSE_ENGINEERING_NOTES.md](docs/REVERSE_ENGINEERING_NOTES.md)

## Samsung Swap APK analysis
The supplied APK is a Flutter AOT release. Its Dart source is not directly available as original source code. The analysis recovered bundled firmware asset names and hashes, board/workflow strings, engine and transport symbols, and activation-related strings. It did not recover a validated packet-level programming protocol or a verified universal license key.

To extract the original APK's selected firmware and board images locally:
```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk
```
The script writes the extracted files under `assets/original_apk/` and prints SHA-256 hashes. The APK itself is not committed to this repository.

## Not yet implemented
This independent app does not yet perform MCU erase, flash write, target verification, or reboot. Static inspection found symbols and UI messages associated with those operations, but symbol names and success strings are not proof of the actual packet format or hardware compatibility. Those operations remain disabled until the exact PCB revision, connector pinout, electrical levels, bootloader protocol, and firmware compatibility are confirmed and tested on safe bench hardware. The original APK's verification mechanism is not modified or bypassed.

## Build locally
```bash
flutter pub get
flutter run
flutter build apk --debug
```

## Safety
Disconnect the refrigerator PCB from mains power before inspection. Inverter capacitors can retain dangerous voltage. Never connect or flash a live board. Use documented low-voltage programming points and qualified bench procedures.
