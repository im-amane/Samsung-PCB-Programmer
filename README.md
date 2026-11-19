# Samsung PCB Programmer

Independent Android app project for Samsung refrigerator inverter PCB service research.

## Download APK
Open the [GitHub Actions builds](https://github.com/im-amane/Samsung-PCB-Programmer/actions/workflows/android.yml). Open the latest successful run and download **samsung-pcb-programmer-debug** under Artifacts.

## Included in this build
- No third-party account, activation, or license-verification flow in this independent app
- PCB profile selector for the currently documented DA41 variants
- USB OTG serial-device discovery and connection
- Import the original Samsung Swap APK locally and extract its three DA41 firmware assets into app memory (the APK and proprietary firmware are not uploaded or committed)
- Firmware file import, strict Motorola S-record structure/checksum/termination validation, address-indexed memory-map parsing, overlap/gap checks, and generic data-block preparation
- Exact SHA-256 fingerprint and selected-profile matching
- Automated firmware-parser unit tests (`flutter test`), run before every CI APK build
- Static-analysis findings from the supplied Samsung Swap APK
- Offline firmware validator checks Motorola S-record counts/checksums and compares extracted file sizes and SHA-256 hashes with the APK reference values (`python3 tools/validate_firmware.py <files...>`)
- Detailed APK findings and exact bundled firmware hashes in [docs/SAMSUNG_SWAP_APK_ANALYSIS.md](docs/SAMSUNG_SWAP_APK_ANALYSIS.md)
- Existing protocol research notes in [docs/REVERSE_ENGINEERING_NOTES.md](docs/REVERSE_ENGINEERING_NOTES.md)
- Renesas 78K0R/uPD78F1201 family research and remaining protocol gates in [docs/RENESAS_PROTOCOL_RESEARCH.md](docs/RENESAS_PROTOCOL_RESEARCH.md)

## Using the app

1. Build/install the Android APK from the latest successful GitHub Actions run.
2. Select the DA41 firmware profile you want to inspect.
3. Tap **Import original Samsung Swap APK** and choose your local `Samsung_Swap.apk`.
4. The app extracts the three known firmware assets in memory. Tap **Load selected firmware from APK**.
5. Check the record/checksum result and the exact SHA-256 profile match.
6. USB scan/connect currently opens the serial port only. It does not assume a baud rate, change boot pins, or send flash commands.

The public repository does not redistribute the original APK or its proprietary firmware assets. Importing the APK on your own device avoids committing those binaries to a public repository.

## Bench testing
Follow [the bench test checklist](docs/BENCH_TEST_CHECKLIST.md) for the next controlled session. The current build supports APK firmware extraction/validation and USB open/close diagnostics only.

## Conversion warning

The original app labels 0459C and 0459G as Double Door and 0459M as Single Door. This is a firmware/profile label mapping, not proof that the 0459M image is compatible with every 0459C/0459G PCB. The app intentionally does not offer erase/write until compatibility and the target protocol are independently validated. See [the firmware comparison report](docs/DA41_FIRMWARE_COMPARISON.md).

## Samsung Swap APK analysis
The supplied APK is a Flutter AOT release. Its Dart source is not directly available as original source code. The app can now import the APK locally and extract the three bundled DA41 firmware assets in memory. Static analysis recovered board/workflow strings, engine and native serial transport clues, and activation-related strings. It did not recover a validated Samsung-board packet-level programming protocol or a verified universal license key. Public Renesas research confirms uPD78F1201 belongs to 78K0R/IB3, but the currently reviewed generic 78K0R programming notes do not establish the Samsung board's exact electrical setup or target command parameters.

To extract the original APK's selected firmware and board images locally:
```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk
```
The script writes the extracted files under `assets/original_apk/` and prints SHA-256 hashes. The APK itself is not committed to this repository.

## Not yet implemented
This independent app does not yet perform MCU erase, flash write, target verification, or reboot. The USB link is deliberately open-only and does not apply the unverified 9600-baud setting from the earlier prototype. Static inspection found symbols and UI messages associated with those operations, but symbol names and success strings are not proof of the actual packet format or hardware compatibility. Those operations remain disabled until the exact PCB revision, connector pinout, electrical levels, bootloader protocol, and firmware compatibility are confirmed and tested on safe bench hardware. The original APK's verification mechanism is not modified or bypassed.

## Build locally
```bash
flutter pub get
flutter run
flutter build apk --debug
```

## Safety
Disconnect the refrigerator PCB from mains power before inspection. Inverter capacitors can retain dangerous voltage. Never connect or flash a live board. Use documented low-voltage programming points and qualified bench procedures.
