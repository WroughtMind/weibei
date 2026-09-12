#!/usr/bin/env python3
"""Report logical App bytes separately from compressed download bytes."""
import json
from pathlib import Path
import plistlib
import sys

app, download = map(Path, sys.argv[1:])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
sections = {}
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        section = path.relative_to(app).parts[1]
        sections[section] = sections.get(section, 0) + path.stat().st_size
print(json.dumps({
    'source_revision': info.get('WeiBeiGitCommit', info.get('LabSourceRevision')),
    'source_dirty': info.get('WeiBeiSourceDirty', info.get('LabSourceDirty')),
    'architecture': info.get('WeiBeiArchitecture', 'unrecorded'),
    'app_logical_bytes': sum(sections.values()),
    'app_sections_bytes': sections,
    'download_file': download.name,
    'download_bytes': download.stat().st_size,
    'units': 'bytes; MB = bytes / 1_000_000; symlinks are not counted twice',
}, indent=2, ensure_ascii=False))
