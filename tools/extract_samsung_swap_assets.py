#!/usr/bin/env python3
"""Extract selected firmware and image assets from the user-supplied Samsung Swap APK."""
import hashlib
import pathlib
import sys
import zipfile

SELECT = {
    "assets/flutter_assets/assets/firmwares/DA41-00814A.mot",
    "assets/flutter_assets/assets/firmwares/DA41-00814D_0459G.mot",
    "assets/flutter_assets/assets/firmwares/DA41-00814D_0459M.bin",
    "assets/flutter_assets/assets/images/app_logo.jpg",
    "assets/flutter_assets/assets/images/samsung_da41_00814d.jpg",
    "assets/flutter_assets/assets/images/samsung_da41_00814d_h.jpg",
    "assets/flutter_assets/assets/images/samsung_da41_00863a.jpg",
}

def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 tools/extract_samsung_swap_assets.py Samsung_Swap.apk")
    apk = pathlib.Path(sys.argv[1])
    out = pathlib.Path("assets/original_apk")
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        present = set(archive.namelist())
        missing = SELECT - present
        if missing:
            raise SystemExit("APK is missing expected assets: " + ", ".join(sorted(missing)))
        for name in sorted(SELECT):
            data = archive.read(name)
            target = out / pathlib.PurePosixPath(name).relative_to("assets/flutter_assets/assets")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            print(f"{target}  {len(data)} bytes  SHA256 {hashlib.sha256(data).hexdigest()}")

if __name__ == "__main__":
    main()
