# Hardware selection for Samsung DA41 programmer

Research date: 2026-11-20

## Target MCU evidence

The Samsung Swap APK contains a clue for Renesas 78K0R / uPD78F1201. This is not a substitute for reading the actual MCU top marking on the user's board. Confirm the exact marking and PCB part/revision before connecting anything.

Renesas' current PG-FP6 supported-device list explicitly includes **uPD78F1201 (78K0R/IB3)** and parameter file **78F1201.pr5**:
- https://www.renesas.com/en/document/mat/list-mcus-supported-pg-fp6

Renesas' recommended 78K0R single-wire UART circuit identifies TOOL0, FLMD0, RESET, VCC and GND connections:
- https://www.renesas.com/en/document/mat/pg-fp6-renesas-flash-programmer-additional-document-users-manual-recommended-circuits-connecting

## Two different purchase paths

### A. Official programmer path (not the Android app's USB adapter)

**Renesas PG-FP6** is the supported commercial programmer option for uPD78F1201. It is listed around ₹79,060 on a current Indian distributor/product listing:
- https://www.renesas.com/en/software-tool/pg-fp6
- https://www.digikey.in/en/products?keywords=PG-FP6

Important: PG-FP6 is a dedicated Renesas programmer with its own target connector and PC/standalone workflow. It is **not** a drop-in USB-UART adapter for the custom Android app being built here. It is expensive; do not buy it just to connect to the Android app.

### B. Prototype path for the custom Android app

A candidate USB interface is the **Waveshare FT232 USB UART Board (Type A), SKU 6170**:
- Manufacturer page: https://www.waveshare.com/ft232-usb-uart-board-type-a.htm
- Indian listing: https://hubtronics.in/communication-modules/wired-communication/ft232-usb-uart-board-type-a

Published specifications say it uses FT232RNL/FT232RL, supports Android, offers 3.3 V / 5 V VCCIO selection, exposes TXD/RXD/RTS#/CTS# on headers and makes other FT232 signals accessible through breakout holes. DTR is available on the FT232 chip, but confirm the exact breakout revision/pads before ordering or designing wiring.

This board is only a **USB serial interface candidate**. It is not, by itself, a safe TOOL0 programmer. Renesas 78K0R uses a single-wire half-duplex TOOL0 link; the design still needs a correctly engineered direction-control/line interface, reset/FLMD0 sequencing, verified voltage levels, and Samsung connector pinout. Do not connect it directly to the PCB.

For app-side bench work, also obtain:
- USB-C OTG adapter (USB-C male to USB-A female), if the Android phone supports USB host/OTG.
- Jumper leads / Dupont female-female set for bench prototyping only.
- A decent digital multimeter for continuity and low-voltage measurements.

Do not buy a generic 3.3/5 V level-shifter board as a presumed solution: TOOL0 is single-wire and direction-sensitive, and the required circuit must be designed for the verified target voltage and interface. Do not power the refrigerator PCB from the USB adapter.

## What should be ordered now?

If the goal is to develop and test the **custom Android app**, the only sensible low-cost candidate to purchase before the board wiring is known is the Waveshare FT232 USB UART Board (Type A), plus a USB-C OTG adapter and basic jumper leads. Even this is for USB enumeration and serial-interface development, not yet for connecting to TOOL0 or flashing.

Do **not** order PG-FP6 unless the goal is to use Renesas' own programmer software/standalone workflow rather than the custom Android app.

## Safety and compatibility gate

1. Confirm MCU top marking is exactly uPD78F1201.
2. Photograph both PCB sides, sticker and connector.
3. Identify every connector pin from reliable Samsung service information or qualified measurements.
4. Confirm target logic voltage and TOOL0 electrical behavior.
5. Design and review the half-duplex TOOL0 interface and reset/FLMD0 driver.
6. Test USB enumeration and the adapter circuit on a safe dummy load before attaching any MCU.
7. Only then enable a read-only signature transaction.
8. Enable erase/write/verify only after read-only communication is stable and a spare board/recovery path is available.

Never connect to a mains-powered refrigerator PCB. Inverter capacitors may retain hazardous voltage after unplugging. A qualified technician must isolate and confirm safe discharge before board work.
