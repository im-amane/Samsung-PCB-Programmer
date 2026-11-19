# Samsung PCB Programmer

Independent Android application project for research and development around Samsung refrigerator inverter PCB programming.

## Current status
This is an early, safe foundation:
- Flutter dashboard and board-profile selection
- Firmware catalogue metadata (no firmware binaries included yet)
- USB OTG connection screen foundation
- No third-party activation or license screen
- Programming/write operations intentionally disabled until the target protocol, connector pinout, board revision, and firmware compatibility are independently verified

## Known research targets
- DA41-00814A / DA92-00459A family
- DA41-00814D / ISB-LC4_3050_V2 visual board family
- uPD78F1201 MCU lead

## Build
Install Flutter stable and Android SDK, then:
```bash
flutter pub get
flutter run
flutter build apk --debug
```

## Safety
Do not connect to a powered refrigerator PCB. Inverter capacitors can retain lethal voltage. Do not erase or write MCU flash until exact hardware and firmware compatibility are confirmed.

## Firmware
Firmware files are deliberately not committed at this stage. Add only files whose provenance, integrity, and exact board compatibility are documented.
