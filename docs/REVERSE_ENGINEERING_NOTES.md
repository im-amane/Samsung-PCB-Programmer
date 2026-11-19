# Samsung Swap APK: static analysis notes

These notes record observations from static inspection of the user-supplied Samsung_Swap.apk. They are research clues, not a validated hardware protocol.

## Firmware assets observed in the APK

- `DA41-00814A.mot`
- `DA41-00814D_0459G.mot`
- `DA41-00814D_0459M.bin`

All three assets contain Motorola S-record text, including the .bin-named 0459M file. The .bin extension is misleading: it contains an S0 header, S3 data records and an S7 termination record. All records passed local byte-count and checksum validation.

The firmware binaries are not copied into this public repository. They remain in the user-supplied APK; import the matching file into the app from a legally obtained source.

## Engine and transport clues

Strings/symbols observed in the compiled Flutter/native payload include:

- `DA41Engine`
- `SerialTransport`
- `writeChunkFast`
- `eraseFlash`
- `verify`
- `Mass Erase 0x20`
- `TOOL0`, `DTR`, and `RTS`
- Signature clue `0xC0`
- MCU-family clue: Renesas 78K0R / uPD78F1201

These names suggest that the original app contains a target-specific programming engine. They do **not** establish exact command packet layouts, baud rate, timing, address mapping, voltage levels, or safe behavior for every board revision.

## Candidate workflow (unconfirmed)

The symbols suggest a possible sequence involving USB serial setup, boot-mode entry using control lines, target synchronization/identification, erase, chunked writes, verification, and reboot. This is only a hypothesis until the exact implementation is decoded and independently tested against the correct board and adapter.

## Current app status

The independent Android app includes USB serial discovery/connection, firmware import, SHA-256 calculation, and Motorola S-record checksum validation. It does not yet send bootloader, erase, write, verify, or reboot commands.

## Validation required before enabling flashing

1. Confirm exact PCB model/revision and MCU marking from clear board photos or service documentation.
2. Confirm connector pinout and adapter wiring with a meter and board documentation.
3. Confirm logic voltage and isolation. Never assume a pin marked 5V is a safe MCU logic level.
4. Decode the complete serial protocol, packet framing, checksums, timeouts, and response codes.
5. Confirm firmware compatibility and address ranges for each board revision.
6. Test read-only identification first, then controlled programming on a spare, isolated board with a recovery path.

Do not connect to a mains-powered refrigerator board. Inverter capacitors can retain hazardous voltage after unplugging. Hardware work should be done only by a qualified technician after safe discharge is confirmed.


## Additional Renesas research

See [RENESAS_PROTOCOL_RESEARCH.md](RENESAS_PROTOCOL_RESEARCH.md) for current public documentation findings. Renesas confirms uPD78F1201 is a 78K0R/IB3 device and is listed for Renesas Flash Programmer V2. The public programmer application note currently inspected is for sibling 78K0R variants, not an exact uPD78F1201-specific command profile. It provides useful family context but is not sufficient to safely enable Samsung-board erase/write commands.
