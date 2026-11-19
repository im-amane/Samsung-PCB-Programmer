# Samsung PCB Programmer

Independent Android app project for Samsung refrigerator inverter PCB service research.

## Download APK
Open the [GitHub Actions builds](https://github.com/im-amane/Samsung-PCB-Programmer/actions/workflows/android.yml). Open the latest successful run and download **samsung-pcb-programmer-debug** under Artifacts.

## Included in this build
- No third-party account, activation, or license-verification flow in this independent app
- Board selector including five board labels recovered from the original AOT snapshot; only three profiles have firmware assets in the supplied APK
- Android USB-host serial discovery/permission using `usb_serial_next` (FTDI, CP210x, CH34x, PL2303 and CDC-ACM), including DTR/RTS, hardware BREAK and USB attach/detach events; native `flutter_libserialport` endpoint discovery/open/close
- Three recovered DA41 firmware assets are bundled in the app and load automatically when their board profile is selected
- Import the original Samsung Swap APK locally to extract its three DA41 firmware assets plus four original image assets into app memory
- Firmware file import, Motorola S-record structure/checksum/termination validation, address-indexed memory-map parsing, overlap/gap checks, and generic data-block preparation
- Renesas 78K0R command/data frame codec with checksums, response validation, ACK/NACK handling, erase/program/verify/signature frame builders, and 16 KB frame-plan preparation
- Testable protocol transaction engine for silicon-signature read and erase/program/verify sequencing, connected to the Android USB serial byte stream for the non-destructive signature diagnostic
- Native serial wire-channel abstraction plus Android USB serial transport with configurable transmit/receive DTR/RTS states, 8N2/8N1 UART configuration, bounded receive buffering, and BREAK control API
- Canonical S-record fingerprint matching that normalizes CRLF/LF and final-newline differences
- Automated firmware and Flutter unit tests, run before each CI APK build
- Static-analysis findings and hardware test checklist

## Original APK asset copying

The original APK is a Flutter AOT release. Its Dart application source is compiled into native AOT libraries, so the original `.dart` source files cannot be copied out of this APK. The independent app must reproduce recovered behavior in its own source.

To extract the three firmware files and four known images:
```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk
```

To copy **all Flutter assets** (firmware, every image, sounds, fonts, shaders, manifests and notices) while preserving their Flutter asset paths:
```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk --all
```

The `--all` option writes into `assets/original_apk/` and keeps the original tree under `assets/original_apk/` (for example, `assets/original_apk/assets/sounds/` and `assets/original_apk/FontManifest.json`). It extracts Flutter assets only; it does not copy compiled app libraries, DEX bytecode, the Android manifest, or resources.arsc. The APK itself is not committed.

## Current implementation boundary

The app currently performs USB/native serial discovery and open/close, automatically loads bundled firmware by selected profile, imports firmware and original APK assets, validates S-records and profile fingerprints, and prepares a protocol plan. The Renesas transaction engine is fake-channel tested and the Android USB byte stream is connected to a read-only silicon-signature diagnostic. The USB serial plugin exposes BREAK, but the app does not yet run a board-specific boot-entry sequence. No erase, write, verify or reboot command is sent to a PCB.

The physical adapter's pinout, logic voltage, TOOL0 direction-control polarity, reset/FLMD0 sequence, serial timing and target compatibility remain unverified. Erase/write must stay disabled until those facts are confirmed from the exact adapter/PCB documentation and tested on safe bench hardware. Never guess pin wiring or firmware compatibility.

## Bench safety

Disconnect the refrigerator PCB from mains power before inspection. Inverter capacitors can retain dangerous voltage. Never connect or flash a live board. Use documented low-voltage programming points and qualified bench procedures.

## Build locally

```bash
flutter pub get
flutter test
flutter build apk --debug
```


## Hardware selection

See [docs/HARDWARE_SELECTION.md](docs/HARDWARE_SELECTION.md) for the verified Renesas PG-FP6 support, a candidate Android-compatible FT232 interface, purchase cautions, and the hardware validation gate. The FT232 board is not a ready-made TOOL0 programmer.
