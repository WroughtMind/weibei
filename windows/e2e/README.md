# Windows packaged UI evidence

These tests launch the real executable produced in `release/win-unpacked`.
They assert the custom title bar, empty launcher, course drawer, three-pane
workspace, settings dialog, and all eight persisted themes.

On Windows:

```powershell
npm run package:dir
npm run test:smoke
```

`WEIBEI_E2E_EXECUTABLE` can point to an explicit packaged `.exe`, or
`WEIBEI_E2E_RELEASE_DIR` can replace the default `release/win-unpacked`
directory. Each test redirects `APPDATA`, `LOCALAPPDATA`, and the WeiBei
library to its Playwright output sandbox, so it never uses the normal profile.

Evidence PNGs are written below `test-results/**/evidence/` at exactly
1240 × 760 CSS pixels with reduced motion and Playwright animations disabled.
They are runtime evidence, not checked-in pixel baselines. A `test:visual`
script is intentionally not defined until reviewed golden images exist.

Linux cannot execute the packaged Windows candidate. It can still validate
the TypeScript and Playwright discovery contract with:

```bash
npm run test:smoke:list
```

The discovered tests are marked skipped outside Windows; Windows CI runs the
same list against the package it just built.
