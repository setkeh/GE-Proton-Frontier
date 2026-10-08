#!/usr/bin/env python3
"""Write a copy of a TrueType font whose style name is empty.

Reproduces the defect in the web font that hangs EVE Frontier's in-game
browser: the Windows subfamily name record (nameID 2) is present but
zero-length, and there is no other record to fall back to. That font only
has Windows-platform names, so the Mac and Unicode style records are
removed rather than emptied: Wine decodes those through a code page, which
turns a zero-length record into "" and hides the bug. The typographic (17)
and WWS (21) subfamily records get the same treatment.

The real font is commercial and cannot be shipped, hence building one.

Usage: make-broken-font.py <in.ttf> <out.ttf>
"""
import struct
import sys

STYLE_NAME_IDS = {2, 17, 21}


def checksum(data: bytes) -> int:
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(f">{len(data) // 4}I", data)) & 0xFFFFFFFF


def main(src: str, dst: str) -> None:
    font = bytearray(open(src, "rb").read())
    if font[:4] not in (b"\0\1\0\0", b"true"):
        sys.exit(f"{src}: not a single TrueType font")

    num_tables = struct.unpack_from(">H", font, 4)[0]
    tables = {}
    for i in range(num_tables):
        entry = 12 + 16 * i
        tag = font[entry:entry + 4].decode("latin-1")
        _, offset, length = struct.unpack_from(">III", font, entry + 4)
        tables[tag] = (entry, offset, length)

    entry, offset, length = tables["name"]
    count = struct.unpack_from(">H", font, offset + 2)[0]
    records = offset + 6
    kept, emptied, removed = [], 0, 0
    for i in range(count):
        record = bytearray(font[records + 12 * i:records + 12 * (i + 1)])
        platform, _, _, name_id = struct.unpack_from(">HHHH", record)
        if name_id in STYLE_NAME_IDS:
            if platform != 3:
                removed += 1
                continue
            struct.pack_into(">H", record, 8, 0)
            emptied += 1
        kept.append(record)
    if not emptied:
        sys.exit(f"{src}: no Windows style name record to empty")
    # String offsets are relative to the storage area, which stays where it
    # is; dropping records only leaves unused bytes in front of it.
    font[records:records + 12 * count] = b"".join(kept) + b"\0" * (12 * removed)
    struct.pack_into(">H", font, offset + 2, len(kept))
    struct.pack_into(">I", font, entry + 4, checksum(bytes(font[offset:offset + length])))

    # head.checkSumAdjustment covers the whole file and must be recomputed last.
    _, head_offset, _ = tables["head"]
    struct.pack_into(">I", font, head_offset + 8, 0)
    struct.pack_into(">I", font, head_offset + 8, (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF)

    open(dst, "wb").write(font)
    print(f"{dst}: emptied {emptied} Windows style name record(s), removed {removed} other(s)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
