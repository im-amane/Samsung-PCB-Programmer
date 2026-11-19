 # Renesas 78K0R programming research

Research date: 2026-11-19

## What is now confirmed

- The supplied Samsung Swap APK contains the MCU label **Renesas 78K0R / uPD78F1201** and strings for TOOL0, DTR, RTS, target synchronization, silicon signature, erase, chunked write and verify.
- Renesas lists **uPD78F1201** as a 78K0R/IB3 device and includes it in the PRM78F1235 parameter-file group for Renesas Flash Programmer V2 / MINICUBE2. Sources:
  - https://www.renesas.com/en/document/mat/list-mcus-supported-renesas-flash-programmer-v2
  - https://www.renesas.com/en/document/mat/flash-memory-programmer-parameter-files-and-supported-mcus
- A Renesas 78K0R programmer application note documents a serial-command programming architecture, programming-mode entry, TOOL0 communication, and command families including status, reset, baud-rate set, chip erase, block erase, programming, verify, blank check and silicon signature. The available application note U18433 is for 78K0R/Kx3, not the exact uPD78F1201 IB3 derivative:
  - https://www.renesas.com/en/document/apn/78k0rkx3-flash-memory-programming-programmer
- Renesas identifies uPD78F1201 as part of the 78K0R/IB3 family, distinct from the 78K0R/Ix3 products covered by application note U19486. Do not silently substitute a sibling MCU's timing, parameter file, or command behavior:
  - https://www.renesas.com/en/document/apn/78k0rkx3-l-78k0rix3-78k0rkx3-c-flash-memory-programmingfor-programmer
- A third-party programmer reference lists generic 78K0R signals as GND, VCC, RESET, TOOL0 and FLMD0 and offers erase/blank-check/program/verify/start operations. This is a useful cross-check only, not Samsung PCB connector documentation:
  - https://www.jcwolfram.de/projekte/uprog2/reference.php

## What this does NOT establish

The research does not establish the Samsung PCB's connector pin numbering, which pins are actually routed, adapter voltage, safe power sequencing, pulse polarity/duration, UART baud rate, synchronization bytes, exact command/data frame bytes, chunk size, status handling, security settings, or whether the 0459M image is compatible with a 0459C/0459G PCB.

The original APK's static strings such as 0xC0, 0x20, and 0x06 are not enough to reconstruct complete command frames. They may represent a signature request, status, or application-specific state, but they must not be treated as standalone command bytes without evidence.

## Engineering work added to the independent app

The app now parses Motorola S-record data into an address-indexed memory map, rejects overlapping records and malformed/count/termination errors, detects address gaps, and prepares generic data blocks. A separate Renesas 78K0R frame codec now builds command/data frames and validates response checksums/status values. It has unit tests for the documented chip-erase frame, reset/signature commands, address-range command, 256-byte data frame and ACK/NACK responses. This codec is not yet connected to the physical USB adapter and sends no commands.

## Gate before enabling actual flashing

1. Confirm the physical MCU marking is exactly uPD78F1201 and record the full PCB part/revision.
2. Obtain the correct Renesas programming documentation/parameter data for the 78K0R/IB3 device, not a sibling device.
3. Confirm the Samsung board's connector and adapter wiring against reliable service documentation and measurements.
4. Confirm target voltage and reset/FLMD0/TOOL0 electrical behavior with suitable isolated bench equipment.
5. Implement only the documented protocol and test synchronization/signature read first.
6. Test erase/write/verify on a spare isolated PCB with a recovery path.
7. Independently establish sensor, relay and refrigerator-model compatibility before treating 0459M as a safe conversion image.

Do not connect an unknown adapter to a refrigerator PCB or attempt erase/write based on generic family-level information. Refrigerator inverter boards can retain hazardous voltage after mains disconnection; work must be performed by a qualified technician after safe discharge is confirmed.
