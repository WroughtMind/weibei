# READY_FOR_PRE_RELEASE_REVIEW

**Date:** 2026-07-19  
**Branch:** `codex/release-1.0-integration`  
**Worktree:** `/Users/changfenhuang/Documents/魏碑-release-1.0`  
**Base:** course `631b2dcc` + rich answer `91eb854d` integrated  

**Status:** `READY_FOR_PRE_RELEASE_REVIEW`

Not done here (explicitly deferred): final LICENSE, privacy/NOTICE legal copy, Developer ID notarize/DMG, VERSION→1.0.0, final release closeout. No push.

---

## Completed stages

| # | Stage | Result |
|---|---|---|
| 1 | Course + rich-answer semantic merge | Done (`c46f0836` lineage) |
| 2 | Top bar locked to compact | Done |
| 3 | Agent surfaces → immersive + selectionFloat + hidden | Done |
| 4 | Layout preset selector removed from settings | Done |
| 5 | Non-focus cinnabar vertical marks reduced | Done |
| 6 | AgentFailureKind + timeout + cancel + retry | Done |
| 7 | Provider settings + about architecture | Done |
| 8 | StudySession material grouping + view all | Done |
| 9 | Loading motion: **A 朱砂墨点** locked | Done (user selected) |
| 10 | P0 PERF collection | Done — no hang-threshold hotspot |
| 11 | Auto-check + packaged app + evidence | Done |

---

## Verification evidence

### Automatic

- `make check` → current equivalent entry; archived check **passed** (`Docs/release-evidence/final-check.log`)
  - WeiBeiSelfCheck, imported identity, web editor, pi-live-check
- `make package` → current equivalent entry; archived package **passed** (`Docs/release-evidence/final-package.log`)
  - App: `dist/魏碑.app`
  - `release_metadata_version=0.1.0` (not bumped; deferred)
  - `release_metadata_source_dirty=true` (expected with uncommitted evidence packing)
- `./script/verify_release_metadata.sh` → after package: version/build/commit printed (`final-metadata.log`)

### Real window captures

- `Docs/release-evidence/app-offline-learning-flow.png`
- `Docs/release-evidence/app-loading-indicator-samples.png`
- `Docs/release-evidence/app-course-workspace-overview-flow.png`
- `Docs/release-evidence/loading-indicator-samples.png` (motion board for choice)

### Performance P0

- `Docs/release-evidence/perf-p0-report.md`
- Samples: `workspace.select` ~12–14ms, `workspace.save` ~9ms — **no ≥100ms hang**
- No behavior-changing perf patch applied

---

## Key product decisions locked in code

1. Top bar = compact constants only  
2. Agent surfaces = immersive conversation + selection float + hidden  
3. Layout settings = free drag + pane toggles + immersive shortcuts; no preset menu in Settings  
4. Red marks = LibraryRow focus retained; other vertical cinnabar marks softened/removed  
5. Failures classified (network/401/429/5xx/timeout/cancel/generic) with Retry  
6. Providers: openai / anthropic / google / openrouter / custom (+ Base URL → models.json)  
7. Sessions: group by material + View All; material switch does not wipe history  
8. Loading motion: ink dots (A)  

---

## Remaining for formal release (out of scope)

- LICENSE file choice  
- Privacy / NOTICE / final About legal copy  
- Developer ID + notarize + DMG  
- VERSION → 1.0.0  
- Final release closeout + push/merge  

---

## Git

```
codex/release-1.0-integration
worktree: /Users/changfenhuang/Documents/魏碑-release-1.0
```

Do **not** push or merge without explicit release instruction.
