#!/usr/bin/env python3
"""Convert a binary patch into a portable C++ header."""
import pathlib
import sys

source = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
data = source.read_bytes()
if not data:
    raise SystemExit(f"empty patch: {source}")
lines = []
for offset in range(0, len(data), 16):
    chunk = data[offset:offset + 16]
    lines.append("    " + ", ".join(f"0x{byte:02x}" for byte in chunk) + ",")
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(
    "#pragma once\n#include <cstdint>\n"
    "inline constexpr uint8_t kEuropePatch[] = {\n"
    + "\n".join(lines)
    + "\n};\n",
    encoding="utf-8",
)
