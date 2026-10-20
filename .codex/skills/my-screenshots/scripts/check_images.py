#!/usr/bin/env python3
"""Check full-screen PNGs and make small sheets for visual inspection."""

import argparse
import hashlib
import json
from pathlib import Path
import textwrap

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--sheets", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--size", help="Expected physical screen size, such as 1206x2622.")
    args = parser.parse_args()
    expected = None
    if args.size:
        try:
            expected = tuple(int(value) for value in args.size.lower().split("x"))
            if len(expected) != 2 or min(expected) <= 0:
                raise ValueError
        except ValueError:
            parser.error("--size must have two positive dimensions: WIDTHxHEIGHT")
    files = sorted(args.directory.glob("*.png"))
    records, errors, duplicates, sizes, hashes = [], [], [], set(), {}
    if not files:
        errors.append("No PNG files found.")
    if args.sheets:
        args.sheets.mkdir(parents=True, exist_ok=True)
    group = []
    sheets = []
    for path in files:
        try:
            with Image.open(path) as source:
                if source.format != "PNG":
                    raise ValueError("File is not a PNG.")
                source.verify()
            with Image.open(path) as source:
                size = source.size
                pixels = source.convert("RGBA")
                digest = hashlib.sha256(str(size).encode() + pixels.tobytes()).hexdigest()
                sizes.add(size)
                records.append({"file": path.name, "width": size[0], "height": size[1]})
                if expected and size != expected:
                    errors.append(f"{path.name}: {size} differs from {expected}.")
                if digest in hashes:
                    duplicates.append([hashes[digest], path.name])
                else:
                    hashes[digest] = path.name
                if args.sheets:
                    thumb = pixels.convert("RGB")
                    thumb.thumbnail((240, 480))
                    group.append((path.name, thumb))
            if len(group) == 12:
                sheets.append(save_sheet(group, args.sheets, len(sheets) + 1))
                group = []
        except (OSError, ValueError, Image.DecompressionBombError) as error:
            errors.append(f"{path.name}: {error}")
    if group:
        sheets.append(save_sheet(group, args.sheets, len(sheets) + 1))
    if len(sizes) > 1:
        errors.append("Mixed dimensions. Check the device sets or full-screen captures.")
    report = {
        "count": len(records), "sizes": sorted(sizes), "duplicates": duplicates,
        "errors": errors, "images": records, "contact_sheets": sheets,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in
                      ("count", "sizes", "duplicates", "errors", "contact_sheets")}))
    return 1 if errors or duplicates else 0


def save_sheet(group, directory, number):
    cell_width, cell_height = 260, 550
    sheet = Image.new("RGB", (cell_width * 4, cell_height * ((len(group) + 3) // 4)), "#dedede")
    draw = ImageDraw.Draw(sheet)
    for index, (name, thumb) in enumerate(group):
        x, y = (index % 4) * cell_width, (index // 4) * cell_height
        sheet.paste(thumb, (x + (cell_width - thumb.width) // 2, y))
        label = "\n".join(textwrap.wrap(f"{index + 1}: {name}", width=36))
        draw.multiline_text((x + 5, y + 485), label, fill="black")
    path = directory / f"sheet-{number:02}.jpg"
    sheet.save(path, quality=90)
    return str(path.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
