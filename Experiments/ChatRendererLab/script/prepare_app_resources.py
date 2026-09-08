#!/usr/bin/env python3
"""Patch only the resolved lab checkout's resource lookups for a macOS .app.

SwiftPM CLI accessors look at the app root, which cannot contain resources in a
valid signed macOS bundle. Prefer Contents/Resources through Bundle.main's
resource API, retaining Bundle.module for command-line use. No rendering changes.
"""
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1]).resolve()
checkouts = {path.name.casefold(): path for path in root.iterdir() if path.is_dir()}
patches = [
    ('swiftmath', 'Sources/SwiftMath/MathBundle/MathFont.swift', 'SwiftMath_SwiftMath', 'Bundle.module', 2),
    ('swiftmath', 'Sources/SwiftMath/MathRender/MTFont.swift', 'SwiftMath_SwiftMath', 'Bundle.module', 1),
    ('highlightr', 'src/classes/Highlightr.swift', 'Highlightr_Highlightr', 'Bundle.module', 1),
    ('litext', 'Sources/Litext/Supplement/LocalizedText.swift', 'Litext_Litext', 'bundle: .module', 5),
]
for identity, relative, bundle, needle, count in patches:
    if identity not in checkouts:
        raise SystemExit(f'Missing resolved lab dependency: {identity}')
    path = checkouts[identity] / relative
    original = path.read_text()
    replacement = (f'(Bundle.main.url(forResource: "{bundle}", withExtension: "bundle")'
                   '.flatMap(Bundle.init(url:)) ?? Bundle.module)')
    if needle == 'bundle: .module':
        replacement = 'bundle: ' + replacement
    if original.count(replacement) == count:
        print(f'already applied: {identity}/{relative}')
        continue
    if original.count(needle) != count or replacement in original:
        raise SystemExit(f'Unexpected resource lookup in {path}; review the resolved version, do not guess.')
    # SwiftPM makes checkout sources read-only. Grant owner-write only for
    # these reviewed local files, then restore their original mode.
    mode = stat.S_IMODE(path.stat().st_mode)
    try:
        path.chmod(mode | stat.S_IWUSR)
        path.write_text(original.replace(needle, replacement))
    finally:
        path.chmod(mode)
    print(f'app-resource lookup: {identity}/{relative} ({count} sites)')
