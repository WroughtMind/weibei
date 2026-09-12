#!/usr/bin/env python3
"""Generate or verify complete editor WOFF2 fonts (no subsetting)."""
from io import BytesIO
from pathlib import Path
import hashlib
import json
import sys

from fontTools.pens.recordingPen import RecordingPen
from fontTools.ttLib import TTFont

root = Path(__file__).resolve().parent.parent
for name in ["Mplus1p-Light", "Mplus1p-Regular"]:
    source = root / "DesignSystem/assets/fonts" / (name + ".ttf")
    target = root / "Sources/WeiBei/Resources/Editor" / (name + ".woff2")
    original = TTFont(source, recalcTimestamp=False)
    original.flavor = "woff2"
    output = BytesIO()
    if "--check" in sys.argv:
        # Compare the shipped font itself: compression bytes differ across CPU architectures.
        output.write(target.read_bytes())
    else:
        original.save(output)
    compressed = TTFont(BytesIO(output.getvalue()), recalcTimestamp=False)
    assert compressed.flavor == "woff2", name
    assert set(original.keys()) == set(compressed.keys()), (name, "tables")
    for field, value in vars(original["head"]).items():
        if field not in {"checkSumAdjustment", "flags"}:
            assert value == getattr(compressed["head"], field), (name, "head", field)
    # WOFF2 sets bit 11 to record its lossless transform; SFNT checksum changes too.
    assert original["head"].flags | (1 << 11) == compressed["head"].flags, (name, "head", "flags")
    assert original.getGlyphOrder() == compressed.getGlyphOrder(), name
    assert original["hmtx"].metrics == compressed["hmtx"].metrics, name
    for tag in original.keys():
        if tag not in {"GlyphOrder", "head", "glyf", "loca"}:
            assert original[tag].compile(original) == compressed[tag].compile(compressed), (name, tag)
    left, right = original.getGlyphSet(), compressed.getGlyphSet()
    for glyph in original.getGlyphOrder():
        a, b = RecordingPen(), RecordingPen()
        left[glyph].draw(a)
        right[glyph].draw(b)
        assert a.value == b.value, (name, glyph, "outline")
        for field in ["xMin", "yMin", "xMax", "yMax", "numberOfContours"]:
            assert getattr(original["glyf"][glyph], field, None) == getattr(compressed["glyf"][glyph], field, None), (name, glyph, field)
        a = getattr(original["glyf"][glyph], "program", None)
        b = getattr(compressed["glyf"][glyph], "program", None)
        assert (a.getBytecode() if a else None) == (b.getBytecode() if b else None), (name, glyph, "hinting")
    if "--check" not in sys.argv:
        target.write_bytes(output.getvalue())
    print(json.dumps({"font": name, "glyphs": len(original.getGlyphOrder()),
                      "unicode_mappings": len(original.getBestCmap()), "source_bytes": source.stat().st_size,
                      "woff2_bytes": len(output.getvalue()), "sha256": hashlib.sha256(output.getvalue()).hexdigest()}))
