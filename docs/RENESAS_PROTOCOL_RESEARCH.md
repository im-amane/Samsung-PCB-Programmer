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

The U19486 UART-mode section specifies an initial **9,600 bps**, no parity, 8 data bits, with **2 stop bits from programmer to MCU and 1 stop bit from MCU to programmer** until a Baud Rate Set command takes effect. It also describes TOOL0 as a physically single-wire line, with the programmer and target taking turns transmitting. The app records and tests these framing constants. U19486 §1.5.2-1.5.3 and §5.2 describe the 78K0R/Ix3 entry sequence: hold RESET low and FLMD0 low, apply VDD, raise FLMD0, wait at least 2 ms (tPR), then release RESET. The target emits a READY 00H pulse; the documented Ix3 timing table gives a READY start window of 4.4-100 ms and a nominal pulse width around 937.5 μs. After READY, the uPD78F1201-specific 78K0R/Ix3 timing table in U19486 §5.2 governs the reset handshake: wait t01 (110.6 μs) before the first 00H at 9600 bps, wait t02 (4.5 μs) between the two 00H bytes, switch to receive direction after the second byte, wait t2C (608.1 μs), then send the Reset command and check its status. This is deliberately different from copying the generic Kx3-L sample labels tCOM/t12. The app waits up to five seconds for the operator to trigger boot entry, checks the READY 00H pulse, and implements separate byte writes, the direction transition and the Ix3 timing waits. Ordinary production command/data transactions use a 100 μs minimum inter-frame wait, which covers the documented 83.8 μs minimum for Verify data; no undocumented faster rate is assumed. The MCU's own READY pulse is specified to occur 4.4-100 ms after RESET release. The app still does **not** drive VDD, FLMD0 or RESET: those controls and their exact Samsung adapter mapping remain unimplemented until the cable's verified wiring is known. These are Renesas family-reference timings for 78K0R/Ix3, not proof of the Samsung board's later selected baud rate or its exact adapter implementation.

## Protocol timing implementation notes

Production Android sessions use a 100 μs ordinary inter-frame delay and three-second receive timeouts. U19486 §5.2 gives 78K0R/Ix3 minima of 83.8 μs from Verify status to Verify data and 13.2 μs from a status frame to the next command; approximately 3 seconds is recommended where no maximum is specified. The reset-entry handshake separately uses t01, t02 and t2C as described above. These are family-reference minima; they do not establish the Samsung adapter's electrical switching delay or prove the Samsung application uses the same timing profile.

## What this does NOT establish

The research does not establish the Samsung PCB's connector pin numbering, which pins are actually routed, adapter voltage, safe power sequencing, pulse polarity/duration, the Samsung app's post-entry baud-rate choice, exact USB-adapter direction switching, Samsung-specific chunk policy, security settings, or whether the 0459M image is compatible with a 0459C/0459G PCB.

The original APK's static strings such as 0xC0, 0x20, and 0x06 are not enough to reconstruct complete command frames. They may represent a signature request, status, or application-specific state, but they must not be treated as standalone command bytes without evidence.

## Engineering work added to the independent app

The app parses Motorola S-record data into an address-indexed memory map, rejects overlapping records and malformed/count/termination errors, detects address gaps, and prepares generic data blocks. The Renesas 78K0R codec builds command/data frames and validates response checksums/status values. A 16 KB plan builder validates a complete 0x0000-0x3FFF image and prepares chip-erase, program, 64 data frames, verify and verify-data frames. The Android USB serial transport is connected to a read-only diagnostic: it checks the raw READY pulse, sends two synchronization bytes, issues the Reset command, then requests and validates the silicon signature. The same transaction is tested through a fake USB byte stream. The destructive program session remains fake-channel tested. The dashboard hard-locks its erase/write action regardless of firmware/signature preflight until hardware commissioning is complete. It has not been bench-tested on a Samsung PCB.

## Gate before enabling actual flashing

1. Confirm the physical MCU marking is exactly uPD78F1201 and record the full PCB part/revision.
2. Obtain the correct Renesas programming documentation/parameter data for the 78K0R/IB3 device, not a sibling device.
3. Confirm the Samsung board's connector and adapter wiring against reliable service documentation and measurements.
4. Confirm target voltage and reset/FLMD0/TOOL0 electrical behavior with suitable isolated bench equipment.
5. Confirm the READY pulse and test the implemented 00H/Reset synchronization and silicon-signature read first; do not infer target power/reset control from DTR/RTS alone.
6. Test erase/write/verify on a spare isolated PCB with a recovery path.
7. Independently establish sensor, relay and refrigerator-model compatibility before treating 0459M as a safe conversion image.

Do not connect an unknown adapter to a refrigerator PCB or attempt erase/write based on generic family-level information. Refrigerator inverter boards can retain hazardous voltage after mains disconnection; work must be performed by a qualified technician after safe discharge is confirmed.


## Additional protocol details checked against U19486EJ1V0AN00

- The Silicon Signature command is not a single response: the target first returns a one-byte ACK status frame, then a separate signature data frame. The data payload contains 27 bytes for the documented fields (vendor, extension/function/device codes, user-flash last address, 10-byte device name, security flag, boot block, flash-shield window and two reserved bytes). The independent codec now validates and parses that complete data frame rather than accepting an arbitrary short payload.
- A Programming command is followed by a status frame for each transmitted data frame. After the final write data frame, the MCU performs an automatic internal verify and returns one additional one-byte status frame. The protocol session now consumes and checks this final status before proceeding to the explicit Verify command.
- The Verify command itself is followed by user-data frames sent from the programmer to the MCU; each data frame receives a two-byte ST1/ST2 status response. Verify result handling must be based on the final response semantics in the target's matching device documentation, not merely on receipt of ACK for each earlier frame.
- The exact U19486 sections are 3.5.1-3.5.4 (programming and final internal-verify status), 3.6.1-3.6.3 (verify data/status), and 3.8.2-3.8.3 (silicon-signature status and payload). Reference: https://www.renesas.com/en/document/apn/78k0rkx3-l-78k0rix3-78k0rkx3-c-flash-memory-programmingfor-programmer

These corrections improve the protocol model and tests only. They do not validate the Samsung adapter wiring or authorize the UI to send flash commands.
