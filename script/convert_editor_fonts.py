#!/usr/bin/env python3
"""Reproduce complete editor WOFF2 fonts with fontTools[woff] (no subsetting)."""
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
    original.save(output)
    compressed = TTFont(BytesIO(output.getvalue()), recalcTimestamp=False)
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
    if "--check" in sys.argv:
        assert target.read_bytes() == output.getvalue(), (name, "generated file differs")
    else:
        target.write_bytes(output.getvalue())
    print(json.dumps({"font": name, "glyphs": len(original.getGlyphOrder()),
                      "unicode_mappings": len(original.getBestCmap()), "source_bytes": source.stat().st_size,
                      "woff2_bytes": len(output.getvalue()), "sha256": hashlib.sha256(output.getvalue()).hexdigest()}))
