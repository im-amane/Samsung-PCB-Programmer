#!/usr/bin/env python3
"""Validate Samsung Swap S-record firmware fingerprints without programming hardware."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import sys

# Raw APK references are retained for provenance. The canonical values below
# normalize CRLF/LF and ensure one final newline so GitHub text copies and APK
# extracted files identify the same firmware data.
EXPECTED = {
    "DA41-00814A.mot": {
        "apk_size": 38924,
        "apk_sha256": "6d51f294e21cdbb2efa207f63fff41c69468eba86199d419578af9a98cac5f02",
        "canonical_size": 38411,
        "canonical_sha256": "674a4e4c632ee167849269e05341d133243a310ab8661c712cbaa179f813e5dc",
    },
    "DA41-00814D_0459G.mot": {
        "apk_size": 38924,
        "apk_sha256": "fc91858a2423324184ef708341e4a6929dfa8b39f53f7c479cbf152bec589873",
        "canonical_size": 38411,
        "canonical_sha256": "d6e23a11b200a61ba5943a760bc9b2fdd0898842b13fad9290a554d5ed128860",
    },
    "DA41-00814D_0459M.bin": {
        "apk_size": 49214,
        "apk_sha256": "4e96a1f2e3c6f39c9af2e61e2f07b69c12123546e4d93365457800e5f76adfc9",
        "canonical_size": 48188,
        "canonical_sha256": "ee709d6f843c429f726953ad7a1550819d8e43bf6d9e6604fd75cbd72d317499",
    },
}


def canonicalize_srecord(data: bytes) -> bytes:
    text = data.decode("ascii")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if not text.endswith("\n"):
        text += "\n"
    return text.encode("ascii")


def validate_srecords(data: bytes) -> tuple[bool, int, str]:
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        return False, 0, "not ASCII S-record text"
    count = 0
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if not re.fullmatch(r"S[0-9][0-9A-Fa-f]+", line):
            return False, count, f"line {number}: malformed S-record"
        try:
            payload = bytes.fromhex(line[2:])
        except ValueError:
            return False, count, f"line {number}: invalid hex data"
        if len(payload) < 2:
            return False, count, f"line {number}: record too short"
        if payload[0] != len(payload) - 1:
            return False, count, f"line {number}: byte count mismatch"
        if sum(payload) & 0xFF != 0xFF:
            return False, count, f"line {number}: checksum mismatch"
        count += 1
    return (count > 0, count, "all S-record checksums valid" if count else "no records")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.files:
        data = path.read_bytes()
        raw_digest = hashlib.sha256(data).hexdigest()
        valid, records, detail = validate_srecords(data)
        expected = EXPECTED.get(path.name)
        try:
            canonical = canonicalize_srecord(data)
            canonical_digest = hashlib.sha256(canonical).hexdigest()
            canonical_size = len(canonical)
        except UnicodeDecodeError:
            canonical_digest = ""
            canonical_size = 0
        size_ok = expected is None or canonical_size == expected["canonical_size"]
        hash_ok = expected is None or canonical_digest == expected["canonical_sha256"]
        ok = valid and size_ok and hash_ok
        print(f"{'PASS' if ok else 'FAIL'} {path.name}")
        print(f"  raw bytes: {len(data)}")
        print(f"  raw sha256: {raw_digest}")
        print(f"  canonical bytes: {canonical_size} ({'match' if size_ok else 'MISMATCH'})")
        print(f"  canonical sha256: {canonical_digest} ({'match' if hash_ok else 'MISMATCH'})")
        print(f"  records: {records}; {detail}")
        if expected is not None:
            print(f"  original APK: {expected['apk_size']} bytes; sha256 {expected['apk_sha256']}")
        else:
            print("  note: no reference fingerprint recorded for this filename")
        failed |= not ok
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
