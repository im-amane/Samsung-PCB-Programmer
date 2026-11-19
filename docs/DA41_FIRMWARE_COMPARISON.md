# DA41 firmware comparison and conversion research

## Source and scope

Source: user-supplied `Samsung_Swap.apk`, inspected on 2026-11-19.

APK SHA-256: `699ccef2eb3d3ccaa13e67c39acab39c661cff1df84900b748715087d715a0c4`

This report records static facts from the APK and its firmware assets. It does not certify hardware compatibility or provide an unverified flash procedure.

## Board labels recovered from the application

| Board profile label | App's refrigerator label | Firmware asset |
|---|---|---|
| DA41-00814A (0459C) | Double Door | `DA41-00814A.mot` |
| DA41-00814D (0459G) | Double Door | `DA41-00814D_0459G.mot` |
| DA41-00814D (0459M) | Single Door | `DA41-00814D_0459M.bin` |

The app also contains labels for DA41-00755A (RT36 Inverter) and DA41-00838A (French Door), but no corresponding firmware assets for those profiles were found in the three-file firmware catalogue.

## Firmware image facts

| Asset | File bytes | Total S-record lines | Data records | Data bytes | Address range |
|---|---:|---:|---:|---:|---|
| DA41-00814A.mot | 38,924 | 513 | 512 | 16,384 | 0x0000–0x3FFF |
| DA41-00814D_0459G.mot | 38,924 | 513 | 512 | 16,384 | 0x0000–0x3FFF |
| DA41-00814D_0459M.bin | 49,214 | 1,026 | 1,024 | 16,384 | 0x0000–0x3FFF |

All records in all three files passed Motorola S-record byte-count and checksum validation. File sizes and SHA-256 values match the extracted APK assets.

| Asset | SHA-256 |
|---|---|
| DA41-00814A.mot | `6d51f294e21cdbb2efa207f63fff41c69468eba86199d419578af9a98cac5f02` |
| DA41-00814D_0459G.mot | `fc91858a2423324184ef708341e4a6929dfa8b39f53f7c479cbf152bec589873` |
| DA41-00814D_0459M.bin | `4e96a1f2e3c6f39c9af2e61e2f07b69c12123546e4d93365457800e5f76adfc9` |

The `.bin` file is still Motorola S-record text: it begins with an S0 header, contains S3 data records, and ends with an S7 termination record. Its extension is not a reliable format indicator.

## Byte-level comparison

All images map the same 16 KB address window. Comparing data bytes at identical addresses:

- 0459G vs 0459M: 7,835 differing byte positions out of 16,384.
- 0459C vs 0459G: 15,146 differing byte positions out of 16,384.
- 0459C vs 0459M: 15,248 differing byte positions out of 16,384.

The 0459G and 0459M firmware therefore are not identical images with a changed label. However, identical MCU capacity/address coverage and a shared DA41-00814D base number do not prove that the 0459M image can be safely programmed onto a 0459G board.

## MCU and serial-programming clues

Static strings identify:

- Renesas 78K0R / uPD78F1201.
- 16 KB flash.
- DA41Engine, SerialTransport and AndroidSerialTransport.
- eraseFlash, writeChunkFast, writeFlash, verify and reboot-related routines.
- TOOL0, DTR and RTS pulse variants.
- Silicon signature query clue 0xC0.
- Mass-erase/status clue 0x20 and status 0x06.

The ARM64 `libserialport.so` exports functions for baud-rate configuration, serial read/write, break signaling, and DTR/RTS control. This confirms the app has low-level serial control capabilities. It does not disclose exact pulse durations, baud rate used for each stage, packet framing, timing, target connector pinout, logic voltage or bootloader state machine. The text `Baud:` is present, but the actual runtime value is not statically established by that string.

## Conversion conclusion

The APK establishes that its own profile catalogue associates 0459C/0459G with Double Door and 0459M with Single Door. It does **not** establish a safe conversion path from a 0459C or 0459G PCB to 0459M firmware.

Before enabling flash operations, the exact donor PCB part number and revision, MCU marking, populated components, connector pinout, logic voltage, sensor/relay mapping and target refrigerator wiring must be checked against reliable service documentation and bench measurements. A wrong firmware can leave the controller unusable or produce unsafe refrigerator operation.

## Current repository implementation

The Flutter app can import the APK locally, extract the three firmware assets in memory, validate S-record structure/checksums, compute SHA-256, and compare the selected asset against the exact profile hash. The APK and proprietary firmware binaries are not committed to this public repository.

USB serial scan/connect/disconnect is implemented as an open-only diagnostic. It does not toggle TOOL0/DTR/RTS, erase flash, write firmware, verify the target or reboot it. These controls remain disabled until protocol and hardware compatibility are established.
