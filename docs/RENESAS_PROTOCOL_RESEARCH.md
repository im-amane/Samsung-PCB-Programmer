 # Renesas 78K0R programming research

Research date: 2026-11-19

## What is now confirmed

- The supplied Samsung Swap APK contains the MCU label **Renesas 78K0R / uPD78F1201** and strings for TOOL0, DTR, RTS, target synchronization, silicon signature, erase, chunked write and verify.
- Renesas lists **uPD78F1201** as a 78K0R/IB3 device and includes it in the PRM78F1235 parameter-file group for Renesas Flash Programmer V2 / MINICUBE2. Sources:
  - https://www.renesas.com/en/document/mat/list-mcus-supported-renesas-flash-programmer-v2
  - https://www.renesas.com/en/document/mat/flash-memory-programmer-parameter-files-and-supported-mcus
- Renesas application note **U19486EJ1V0AN00** explicitly lists μPD78F1201 among its applicable devices and includes the 78K0R/Ix3 silicon-signature table naming 78F1201/78F1203. It documents the command/data frame format, UART mode, programming-mode entry, TOOL0 communication, reset, baud-rate set, chip erase, block erase, programming, verify, blank check and silicon-signature commands. This is the correct family-level programmer reference for the MCU named by the APK:
  - https://www.renesas.com/en/document/apn/78k0rkx3-l-78k0rix3-78k0rkx3-c-flash-memory-programmingfor-programmer

  Renesas note U18433 is a separate 78K0R/Kx3 programmer note and should not be confused with U19486:
  - https://www.renesas.com/en/document/apn/78k0rkx3-flash-memory-programming-programmer
- The U19486 document lists uPD78F1201 in the applicable-device table and its Ix3 silicon-signature table lists 78F1201/78F1203. It uses the Kx3-L as the representative device and cautions readers to consult the corresponding device user manual for device-specific characteristics. The 78K0R/IB3 hardware user manual is U19018E. Device-specific electrical/timing parameters and Samsung-board wiring still require confirmation; do not substitute another device's parameter values.
- A third-party programmer reference lists generic 78K0R signals as GND, VCC, RESET, TOOL0 and FLMD0 and offers erase/blank-check/program/verify/start operations. This is a useful cross-check only, not Samsung PCB connector documentation:
  - https://www.jcwolfram.de/projekte/uprog2/reference.php

## UART entry details confirmed in U19486

The U19486 UART-mode section specifies an initial **9,600 bps**, no parity, 8 data bits, with **2 stop bits from programmer to MCU and 1 stop bit from MCU to programmer** until a Baud Rate Set command takes effect. It also describes the TOOL0 line as physically single-wire, with the programmer and target taking turns transmitting. The app now records these initial framing constants in the protocol module and tests them. These are Renesas family-reference settings, not proof of the Samsung app's later selected baud rate or its exact USB-adapter implementation. The application note also documents programming-mode entry using VDD, FLMD0 and RESET sequencing; the required board-specific power and timing values must be verified before implementing that sequence.

## What this does NOT establish

The research does not establish the Samsung PCB's connector pin numbering, which pins are actually routed, adapter voltage, safe power sequencing, pulse polarity/duration, the Samsung app's post-entry baud-rate choice, exact USB-adapter direction switching, Samsung-specific chunk policy, security settings, or whether the 0459M image is compatible with a 0459C/0459G PCB.

The original APK's static strings such as 0xC0, 0x20, and 0x06 are not enough to reconstruct complete command frames. They may represent a signature request, status, or application-specific state, but they must not be treated as standalone command bytes without evidence.

## Engineering work added to the independent app

The app now parses Motorola S-record data into an address-indexed memory map, rejects overlapping records and malformed/count/termination errors, detects address gaps, and prepares generic data blocks. A separate Renesas 78K0R frame codec now builds command/data frames and validates response checksums/status values. A 16 KB plan builder validates a complete 0x0000-0x3FFF image and prepares chip-erase, program, 64 data frames, verify and verify-data frames. Unit tests cover documented frame vectors and plan preparation. Neither the codec nor the plan is connected to the physical USB adapter; the app sends no commands.

## Gate before enabling actual flashing

1. Confirm the physical MCU marking is exactly uPD78F1201 and record the full PCB part/revision.
2. Obtain the correct Renesas programming documentation/parameter data for the 78K0R/IB3 device, not a sibling device.
3. Confirm the Samsung board's connector and adapter wiring against reliable service documentation and measurements.
4. Confirm target voltage and reset/FLMD0/TOOL0 electrical behavior with suitable isolated bench equipment.
5. Implement only the documented protocol and test synchronization/signature read first.
6. Test erase/write/verify on a spare isolated PCB with a recovery path.
7. Independently establish sensor, relay and refrigerator-model compatibility before treating 0459M as a safe conversion image.

Do not connect an unknown adapter to a refrigerator PCB or attempt erase/write based on generic family-level information. Refrigerator inverter boards can retain hazardous voltage after mains disconnection; work must be performed by a qualified technician after safe discharge is confirmed.
