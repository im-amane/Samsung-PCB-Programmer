# Bench test checklist for Samsung PCB Programmer

This checklist is for the next controlled bench session. The current app is a firmware inspection and USB connection diagnostic tool, not a confirmed flasher.

## Before connecting anything

- [ ] Refrigerator is unplugged from mains.
- [ ] PCB has been removed/isolated by a qualified person and stored safely.
- [ ] Exact PCB sticker part number and full revision suffix have been photographed.
- [ ] MCU top marking has been photographed and checked against the expected Renesas 78K0R / uPD78F1201 identification.
- [ ] Programmer adapter model and its output logic voltage are confirmed from its documentation.
- [ ] Connector pinout is confirmed from reliable board/service documentation. Do not guess VCC, GND, RX, TX, TOOL0, DTR or RTS.
- [ ] No USB-UART signal is connected to a pin until its electrical level and function are confirmed.

## App checks

1. Install the latest successful **samsung-pcb-programmer-debug** artifact from GitHub Actions.
2. Open the app and select each firmware profile in turn.
3. Import the supplied Samsung Swap APK from local storage.
4. Confirm that the app reports all three firmware assets extracted.
5. Load each profile and check its exact SHA-256 match, S-record validation, payload size and address range.
6. Expected firmware payload: 16,384 bytes, address range 0x0000–0x3FFF.
7. Use Scan USB with the programmer connected to the phone via a suitable OTG adapter.
8. Confirm that the adapter is listed, connect, then disconnect.
9. Confirm that no flash command is sent. The current app does not set an assumed baud rate or toggle boot pins.

## Expected catalogue fingerprints

| Profile | Firmware | Expected data bytes | Address range |
|---|---|---:|---|
| 0459C Double Door | DA41-00814A.mot | 16,384 | 0x0000–0x3FFF |
| 0459G Double Door | DA41-00814D_0459G.mot | 16,384 | 0x0000–0x3FFF |
| 0459M Single Door | DA41-00814D_0459M.bin | 16,384 | 0x0000–0x3FFF |

## Conversion is not yet approved

The app's labels associate 0459C/0459G with Double Door and 0459M with Single Door. This is not proof that 0459M is safe for a 0459C/0459G PCB. Do not attempt erase/write during this session. First establish exact PCB revision, populated hardware, connector pinout, logic voltage, sensor/relay mapping and compatibility using reliable service information.

## What to capture for the next engineering step

- Clear photo of the full PCB, both sides.
- Close photo of the PCB sticker/part number.
- Close photo of the MCU marking.
- Clear photo of the programming connector and silkscreen labels.
- Programmer adapter make/model and voltage specification.
- Refrigerator model number (not a serial number).
- Whether the board is 0459C, 0459G or another revision, based on its physical markings rather than the firmware selector.

Do not send refrigerator serial numbers, personal details, or photos containing identifying information.
