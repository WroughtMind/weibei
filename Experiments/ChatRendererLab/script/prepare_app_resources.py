#!/usr/bin/env python3
"""Patch resolved checkouts' resources, attachment ownership and cold highlighting.

SwiftPM CLI accessors look at the app root, which cannot contain resources in a
valid signed macOS bundle. Prefer Contents/Resources through Bundle.main's
resource API, retaining Bundle.module for command-line use.
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

# Litext 2.2.1 stores a delegate that retains its owning Attachment. Let the
# attributed string own the delegate instead, so recycled rows release it.
path = checkouts['litext'] / 'Sources/Litext/TextLabelView/Attachments/TextLabel+Attachment.swift'
original = path.read_text()
changes = [
    ('        private var cachedRunDelegate: CTRunDelegate?\n', ''),
    ('            if let cachedRunDelegate {\n                return cachedRunDelegate\n            }\n\n', ''),
    ('            cachedRunDelegate = delegate\n', ''),
    ('        /// The delegate is cached so repeated reads do not allocate additional delegates or retain\n        /// the attachment more than once.\n',
     '        /// The attributed string owns the delegate; caching it here would retain self forever.\n'),
]
if 'cachedRunDelegate' not in original:
    print('already applied: Litext attachment ownership')
else:
    for before, after in changes:
        if original.count(before) != 1:
            raise SystemExit('Unexpected Litext attachment implementation; review the locked dependency.')
        original = original.replace(before, after)
    mode = stat.S_IMODE(path.stat().st_mode)
    try:
        path.chmod(mode | stat.S_IWUSR)
        path.write_text(original)
    finally:
        path.chmod(mode)
    print('Litext attachment delegate no longer retains its owner in a cycle')

# MarkdownView already highlights on its worker. Its separate synchronous API
# must not create an unused JavaScript engine on the first main-thread cache read.
path = checkouts['markdownview'] / 'Sources/MarkdownView/Components/CodeView/CodeHighlighter.swift'
original = path.read_text()
before = '    private let highlightr = Highlightr()\n'
after = '''    private lazy var highlightr: Highlightr? = {
        let value = Highlightr()
        value?.setTheme(to: "xcode")
        return value
    }()
'''
initializer = '    private init() {\n        highlightr?.setTheme(to: "xcode")\n    }'
if after in original:
    print('already applied: lazy synchronous code highlighter')
else:
    if original.count(before) != 1 or original.count(initializer) != 1:
        raise SystemExit('Unexpected MarkdownView highlighter; review the locked dependency.')
    mode = stat.S_IMODE(path.stat().st_mode)
    try:
        path.chmod(mode | stat.S_IWUSR)
        path.write_text(original.replace(before, after).replace(initializer, '    private init() {}'))
    finally:
        path.chmod(mode)
    print('Unused synchronous highlighter no longer initializes during async rendering')
