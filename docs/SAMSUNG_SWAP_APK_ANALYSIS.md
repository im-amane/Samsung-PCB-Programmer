# Samsung Swap APK analysis

Analysis date: 2026-11-19
Input: user-supplied `Samsung_Swap.apk` (54,540,630 bytes)

## Package structure

- Flutter Android application; Dart business logic is AOT-compiled into `lib/<abi>/libapp.so`.
- APK contains ARM64, ARMv7 and x86_64 Flutter runtimes and app libraries.
- App assets are under `assets/flutter_assets/`.
- A direct source-code copy is not available from this release APK. Reimplementation must follow recovered behavior and validated tests.

## Confirmed bundled firmware

| APK asset | Size | Original APK SHA-256 | Canonical S-record SHA-256 (LF + final newline) |
|---|---:|---|---|
| `firmwares/DA41-00814A.mot` | 38,924 | `6d51f294e21cdbb2efa207f63fff41c69468eba86199d419578af9a98cac5f02` | `674a4e4c632ee167849269e05341d133243a310ab8661c712cbaa179f813e5dc` |
| `firmwares/DA41-00814D_0459G.mot` | 38,924 | `fc91858a2423324184ef708341e4a6929dfa8b39f53f7c479cbf152bec589873` | `d6e23a11b200a61ba5943a760bc9b2fdd0898842b13fad9290a554d5ed128860` |
| `firmwares/DA41-00814D_0459M.bin` | 49,214 | `4e96a1f2e3c6f39c9af2e61e2f07b69c12123546e4d93365457800e5f76adfc9` | `ee709d6f843c429f726953ad7a1550819d8e43bf6d9e6604fd75cbd72d317499` |

The third file begins with an S-record text header despite its `.bin` extension. Do not infer format solely from extension. All three extracted files were independently checked: 513, 513 and 1,026 S-records respectively; every record count and checksum passed, and all byte sizes and SHA-256 hashes matched the APK reference values. Run `python3 tools/validate_firmware.py <files...>` to repeat these checks.

## Confirmed UI / workflow strings

Recovered strings identify these user-facing operations and states:

- Board selection: `DA41-00814A (0459C Double Door)`, `DA41-00814D (0459G Double Door)`, `DA41-00814D (0459M Single Door)`, plus other board labels including `DA41-00755A` and `DA41-00838A`.
- Load bundled firmware: `loadBundledFirmware`; firmware parse: `parseFirmware`.
- Connection states: `Connecting to Target Board (DA41 Link)`, `SUCCESS: Samsung DA41 target board is CONNECTED & READY!`.
- Programming workflow strings: mass erase, chunked write, verify, and reboot to normal RUN mode.
- Relevant compiled symbols include `DA41Engine`, `SerialTransport`, `AndroidSerialTransport`, `eraseFlash`, `writeChunkFast`, `verify`.

These strings prove that the APK contains labels/symbols for these operations. Renesas application note U19486EJ1V0AN independently documents the 78K0R/IB3 programmer frame protocol and explicitly lists uPD78F1201 as an applicable device. The independent repository implements a tested frame codec based on that Renesas document. This does not prove the original APK uses every documented option identically or that the Samsung PCB wiring/transport is electrically compatible.

## Activation / licensing observations

Strings include `ActivationScreen`, `LicenseService`, `getDeviceCode`, `verifyTokenT`, `license_key`, `license_type`, `SK9988`, and a local file path:

`/data/data/com.skelectronics.samsung_swap/files/license.json`

The APK also contains the message that a device code should be sent to S.K Electronics for a license key. This is evidence of an activation UI and local license storage. It does not establish a universal activation key or reveal a verified key-generation/validation algorithm. This project uses its own independent implementation and does not patch or bypass the original APK's activation checks.

## Network observation

The APK's binary Android manifest and DEX were checked for the standard `INTERNET` and `ACCESS_NETWORK_STATE` permission strings; neither was found. No definite vendor API hostname was recovered from the app binary strings. This is evidence against an ordinary Android internet-backed activation flow in this build, but is not absolute proof that no external communication can occur through another component or a separate companion service.

## Asset inventory and extraction

The APK contains Flutter assets including the three firmware files, four board/application JPEGs, audio effects, Flutter font manifests, Material/Cupertino icon fonts, shader files and Flutter notices. To extract the three known firmware files and four known images:

```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk
```

To extract every file under `assets/flutter_assets/` while preserving its relative path:

```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk --all
```

The extractor intentionally does not extract `libapp.so`, native libraries, DEX bytecode, Android manifest or `resources.arsc` as if they were editable Dart source. Compiled AOT code is not a source-code archive.

## Important implementation boundary

The current app provides USB serial discovery/open/disconnect, firmware import, raw SHA-256 and S-record checksum checks, canonical S-record fingerprint matching (normalizing CRLF/LF and final-newline differences), address-indexed memory-map parsing, and a tested Renesas 78K0R command/data frame codec. It can prepare a complete 16 KB erase/program/verify frame plan for an exact firmware match. The plan is not sent to hardware. The native serial transport can configure line settings and control BREAK/DTR/RTS, and the wire-channel abstraction accepts adapter-specific direction callbacks, but the dashboard does not connect these pieces to the physical USB session.

Erase/write controls remain disabled until the exact PCB revision, connector pinout, logic voltage, single-wire TOOL0 adapter behavior, RESET/FLMD0 control and firmware compatibility are confirmed and tested on safe bench hardware.

## Firmware map comparison

All three firmware assets contain exactly 16,384 data bytes mapped from address `0x0000` through `0x3FFF`, matching the app's 16 KB MCU label:

| Firmware | S-record data records | Data bytes | Address range |
|---|---:|---:|---|
| `DA41-00814A.mot` | 512 | 16,384 | `0x0000–0x3FFF` |
| `DA41-00814D_0459G.mot` | 512 | 16,384 | `0x0000–0x3FFF` |
| `DA41-00814D_0459M.bin` | 1,024 | 16,384 | `0x0000–0x3FFF` |

The 0459G and 0459M images cover the same address range but differ at 7,835 byte positions. The 0459C and 0459G images differ at 15,146 positions. These comparisons show the images are materially different firmware builds, not merely different filenames or S-record line layouts. They do **not** prove cross-model compatibility or that a Double Door PCB can be converted by writing the 0459M image.

## Native serial stack recovered from APK

The APK registers Android USB serial drivers and the Flutter plugin `flutter_libserialport`, and bundles `libserialport.so` for ARM64, ARMv7 and x86_64. The native library exports serial read/write, port open/close, BREAK, DTR/RTS and serial configuration functions. This confirms low-level serial-control capability in the APK, but not the exact Samsung adapter pinout, pulse durations, polarity, target wiring or safe electrical levels.
