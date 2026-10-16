"""Check actual runner PE mitigation metadata, not just build switches."""
import argparse
import json
from pathlib import Path
import struct


def check_runner(path):
    path = Path(path)
    with path.open("rb") as source:
        size = path.stat().st_size

        def read(offset, length):
            if offset < 0 or length < 0 or offset + length > size:
                raise ValueError("Truncated runner PE metadata")
            source.seek(offset)
            data = source.read(length)
            if len(data) != length:
                raise ValueError("Short runner PE metadata")
            return data

        dos = read(0, 64)
        if dos[:2] != b"MZ":
            raise ValueError("Not a PE runner")
        start = struct.unpack_from("<I", dos, 60)[0]
        header = read(start, 24)
        if header[:4] != b"PE\0\0":
            raise ValueError("Invalid runner signature")
        machine, count = struct.unpack_from("<HH", header, 4)
        optional_size = struct.unpack_from("<H", header, 20)[0]
        if machine != 0x8664 or not 1 <= count <= 96 or not 240 <= optional_size <= 4096:
            raise ValueError("Expected bounded Windows x64 runner")
        optional = read(start + 24, optional_size)
        if struct.unpack_from("<H", optional)[0] != 0x20B:
            raise ValueError("Expected PE32+ runner")
        flags = struct.unpack_from("<H", optional, 70)[0]
        if flags & 0x4160 != 0x4160:
            raise ValueError("Runner missing ASLR/high-entropy ASLR/DEP/CFG")
        if struct.unpack_from("<I", optional, 108)[0] <= 10:
            raise ValueError("Runner missing load configuration")
        rva, length = struct.unpack_from("<II", optional, 112 + 10 * 8)
        if length < 148:
            raise ValueError("Runner missing mitigation load configuration")
        config = None
        for index in range(count):
            section = read(start + 24 + optional_size + index * 40, 40)
            _, address, raw_size, raw_offset = struct.unpack_from("<IIII", section, 8)
            delta = rva - address
            if 0 <= delta and delta + 148 <= raw_size:
                config = read(raw_offset + delta, 148)
                break
        if config is None or struct.unpack_from("<I", config)[0] < 148:
            raise ValueError("Runner load configuration is not file-backed")
        if struct.unpack_from("<H", config, 78)[0] != 0xA00:
            raise ValueError("Runner static DLL search restriction missing")
        if not struct.unpack_from("<Q", config, 88)[0]:
            raise ValueError("Runner stack security cookie missing")
        if struct.unpack_from("<I", config, 144)[0] & 0x500 != 0x500:
            raise ValueError("Runner CFG instrumentation/table missing")
        if not struct.unpack_from("<Q", config, 136)[0]:
            raise ValueError("Runner CFG function table is empty")
    return {"runner": path.name, "aslr": True, "highEntropyAslr": True,
            "dep": True, "cfg": True, "stackCookie": True,
            "dependentLoadFlags": "0xA00"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runner")
    args = parser.parse_args()
    try:
        print(json.dumps(check_runner(args.runner)))
    except (ValueError, OSError, struct.error) as error:
        parser.exit(1, f"Runner hardening validation failed: {error}\n")
