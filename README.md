# Samsung PCB Programmer

Independent Android app project for Samsung refrigerator inverter PCB service research.

## Download APK
Open the [GitHub Actions builds](https://github.com/im-amane/Samsung-PCB-Programmer/actions/workflows/android.yml). Open the latest successful run and download **samsung-pcb-programmer-debug** under Artifacts.

## Included in this build
- No third-party account, activation, or license-verification flow in this independent app
- Board selector including all five board labels recovered from the original AOT snapshot; only the three profiles with firmware assets in the supplied APK are marked firmware-backed
- USB OTG serial-device discovery and connection
- Import the original Samsung Swap APK locally and extract its three DA41 firmware assets plus four original image assets (app logo and board references) into app memory; the APK and extracted binaries are not uploaded or committed
- Firmware file import, strict Motorola S-record structure/checksum/termination validation, address-indexed memory-map parsing, overlap/gap checks, and generic data-block preparation
- Renesas 78K0R command/data frame codec with checksums, response validation, ACK/NACK handling, erase/program/verify/signature frame builders, complete 16 KB frame-plan preparation, and unit tests
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
4. The app extracts the three known firmware assets and four original image assets in memory. The original app logo and DA41-00814D board references are then displayed. Tap **Load selected firmware from APK**.
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
This independent app has the Renesas 78K0R frame codec, but does not yet execute MCU erase, flash write, target verification, or reboot over USB. The physical transport must support the documented single-wire TOOL0 UART behavior, asymmetric programmer/target stop-bit handling, and the board's RESET/FLMD0 control. The exact Samsung connector pinout, adapter electrical levels, stop-bit/direction handling, and 0459M cross-model compatibility must be confirmed before enabling the hardware operations. No programming command is sent by the current app. The original APK's verification mechanism is not modified or bypassed.

## Build locally
```bash
flutter pub get
flutter run
flutter build apk --debug
```

## Safety
Disconnect the refrigerator PCB from mains power before inspection. Inverter capacitors can retain dangerous voltage. Never connect or flash a live board. Use documented low-voltage programming points and qualified bench procedures.
