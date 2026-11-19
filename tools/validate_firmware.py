#!/usr/bin/env python3
"""Validate extracted Samsung Swap firmware files without programming hardware."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import sys

EXPECTED = {
    "DA41-00814A.mot": (38924, "6d51f294e21cdbb2efa207f63fff41c69468eba86199d419578af9a98cac5f02"),
    "DA41-00814D_0459G.mot": (38924, "fc91858a2423324184ef708341e4a6929dfa8b39f53f7c479cbf152bec589873"),
    "DA41-00814D_0459M.bin": (49214, "4e96a1f2e3c6f39c9af2e61e2f07b69c12123546e4d93365457800e5f76adfc9"),
}


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
        payload = bytes.fromhex(line[2:])
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
        digest = hashlib.sha256(data).hexdigest()
        valid, records, detail = validate_srecords(data)
        expected = EXPECTED.get(path.name)
        size_ok = expected is None or len(data) == expected[0]
        hash_ok = expected is None or digest == expected[1]
        ok = valid and size_ok and hash_ok
        print(f"{'PASS' if ok else 'FAIL'} {path.name}")
        print(f"  bytes: {len(data)} ({'match' if size_ok else 'MISMATCH'})")
        print(f"  sha256: {digest} ({'match' if hash_ok else 'MISMATCH'})")
        print(f"  records: {records}; {detail}")
        if expected is None:
            print("  note: no reference hash recorded for this filename")
        failed |= not ok
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
