#!/usr/bin/env python3
"""Extract original Samsung Swap Flutter assets from a user-supplied APK.

By default, extracts the three known firmware files and four board/application
images to assets/original_apk/. Pass --all to extract every file under
assets/flutter_assets/ (manifests, fonts, sounds, shaders, notices, images and
firmware) while preserving the original Flutter asset directory structure.
The APK's compiled Dart/native code is not source code and is not extracted.
"""
import argparse
import hashlib
import pathlib
import zipfile

DEFAULT_SELECT = {
    "assets/flutter_assets/assets/firmwares/DA41-00814A.mot",
    "assets/flutter_assets/assets/firmwares/DA41-00814D_0459G.mot",
    "assets/flutter_assets/assets/firmwares/DA41-00814D_0459M.bin",
    "assets/flutter_assets/assets/images/app_logo.jpg",
    "assets/flutter_assets/assets/images/samsung_da41_00814d.jpg",
    "assets/flutter_assets/assets/images/samsung_da41_00814d_h.jpg",
    "assets/flutter_assets/assets/images/samsung_da41_00863a.jpg",
}


def extract_apk_assets(apk_path, output_dir, include_all=False):
    apk_path = pathlib.Path(apk_path)
    output_dir = pathlib.Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(apk_path) as archive:
        files = [
            name for name in archive.namelist()
            if not name.endswith("/") and name.startswith("assets/flutter_assets/")
        ]
        if include_all:
            selected = sorted(files)
            if not selected:
                raise ValueError("APK contains no assets/flutter_assets files")
        else:
            missing = DEFAULT_SELECT - set(files)
            if missing:
                raise ValueError(
                    "APK is missing expected assets: " + ", ".join(sorted(missing))
                )
            selected = sorted(DEFAULT_SELECT)

        extracted = []
        for name in selected:
            data = archive.read(name)
            relative = pathlib.PurePosixPath(name).relative_to(
                "assets/flutter_assets"
            ) if include_all else pathlib.PurePosixPath(name).relative_to(
                "assets/flutter_assets/assets"
            )
            target = output_dir / pathlib.Path(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            digest = hashlib.sha256(data).hexdigest()
            extracted.append((target, len(data), digest))
    return extracted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", help="Path to the original Samsung_Swap.apk")
    parser.add_argument(
        "--all",
        action="store_true",
        help="extract every Flutter asset, not just the known firmware and images",
    )
    parser.add_argument(
        "--output",
        default="assets/original_apk",
        help="output directory (default: assets/original_apk)",
    )
    args = parser.parse_args()

    try:
        extracted = extract_apk_assets(args.apk, args.output, args.all)
    except (OSError, zipfile.BadZipFile, ValueError) as exc:
        parser.error(str(exc))

    print(f"Extracted {len(extracted)} file(s):")
    for path, size, digest in extracted:
        print(f"{path}  {size} bytes  SHA256 {digest}")


if __name__ == "__main__":
    main()
