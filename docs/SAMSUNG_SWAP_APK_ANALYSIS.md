# Samsung Swap APK analysis

Analysis date: 2026-11-19
Input: user-supplied `Samsung_Swap.apk` (54,540,630 bytes)

## Package structure

- Flutter Android application; Dart business logic is AOT-compiled into `lib/<abi>/libapp.so`.
- APK contains ARM64, ARMv7 and x86_64 Flutter runtimes and app libraries.
- App assets are under `assets/flutter_assets/assets/`.
- A direct source-code copy is not available from this release APK. Reimplementation must follow recovered behavior and validated tests.

## Confirmed bundled firmware

| APK asset | Size | SHA-256 |
|---|---:|---|
| `firmwares/DA41-00814A.mot` | 38,924 | `6d51f294e21cdbb2efa207f63fff41c69468eba86199d419578af9a98cac5f02` |
| `firmwares/DA41-00814D_0459G.mot` | 38,924 | `fc91858a2423324184ef708341e4a6929dfa8b39f53f7c479cbf152bec589873` |
| `firmwares/DA41-00814D_0459M.bin` | 49,214 | `4e96a1f2e3c6f39c9af2e61e2f07b69c12123546e4d93365457800e5f76adfc9` |

The third file begins with an S-record text header despite its `.bin` extension. Do not infer format solely from extension. All three extracted files were independently checked: 513, 513 and 1,026 S-records respectively; every record count and checksum passed, and all byte sizes and SHA-256 hashes matched the APK reference values. Run `python3 tools/validate_firmware.py <files...>` to repeat these checks.

## Confirmed UI / workflow strings

Recovered strings identify these user-facing operations and states:

- Board selection: `DA41-00814A (0459C Double Door)`, `DA41-00814D (0459G Double Door)`, `DA41-00814D (0459M Single Door)`, plus other board labels including `DA41-00755A` and `DA41-00838A`.
- Load bundled firmware: `loadBundledFirmware`; firmware parse: `parseFirmware`.
- Connection states: `Connecting to Target Board (DA41 Link)`, `SUCCESS: Samsung DA41 target board is CONNECTED & READY!`.
- Programming workflow strings: mass erase, chunked write, verify, and reboot to normal RUN mode.
- Relevant compiled symbols include `DA41Engine`, `SerialTransport`, `AndroidSerialTransport`, `eraseFlash`, `writeChunkFast`, `verify`.

These strings prove that the APK contains labels/symbols for these operations. They do **not** prove exact packet bytes, timing, transport configuration, or that the workflow succeeds on every board.

## Activation / licensing observations

Strings include `ActivationScreen`, `LicenseService`, `getDeviceCode`, `verifyTokenT`, `license_key`, `license_type`, `SK9988`, and a local file path:

`/data/data/com.skelectronics.samsung_swap/files/license.json`

The APK also contains the message that a device code should be sent to S.K Electronics for a license key. This is evidence of an activation UI and local license storage. It does not establish a universal activation key or reveal a verified key-generation/validation algorithm. This project will use its own independent access policy and will not patch or bypass the original APK's activation checks.

## Network observation

The APK's binary Android manifest and DEX were checked for the standard `INTERNET` and `ACCESS_NETWORK_STATE` permission strings; neither was found. No definite vendor API hostname was recovered from the app binary strings. This is evidence against an ordinary Android internet-backed activation flow in this build, but is not absolute proof that no external communication can occur through another component or a separate companion service.

## Important implementation boundary

The existing repository currently provides USB serial discovery/open/disconnect, firmware import, SHA-256 and S-record checksum checks, and exact filename-plus-SHA-256 matching against the selected APK board profile. The recovered APK has stronger programming workflow labels, but the actual target protocol is not validated in this repository. Erase/write controls must remain disabled until the exact PCB revision, connector pinout, logic voltage, programmer transport and command framing are established from reliable evidence and tested on safe bench hardware.

## Extracting the exact APK assets

Run:

```bash
python3 tools/extract_samsung_swap_assets.py /path/to/Samsung_Swap.apk
```

The script extracts the three firmware files and four board/application images into `assets/original_apk/`, prints SHA-256 hashes, and does not modify the APK.
