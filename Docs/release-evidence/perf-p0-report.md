# Performance P0 — final features + loading motion

**Date:** 2026-07-19  
**Branch:** `codex/release-1.0-integration`  
**Gate:** `WEIBEI_PERF=1` → `[PERF-weibei-2]` lines (threshold ≥ 8ms)

## Scenarios

| Scenario | Capture | Notes |
|---|---|---|
| `offline-learning-flow` | yes | agent + learning path |
| `loading-indicator-samples` | yes | final ink-dots loading board |
| `immersive-conversation-flow` | yes | immersive chat host |

## Samples ≥ 8ms

```
[PERF-weibei-2] name=workspace.select ms=14.4
[PERF-weibei-2] name=workspace.save ms=9.3
[PERF-weibei-2] name=workspace.select ms=12.4
```

## Conclusion

- No main-thread sample ≥ 100ms (hang threshold).
- `workspace.save` ≈ 9ms and `workspace.select` ≈ 12–14ms are measurable but not P0 hang material on this workspace density.
- Heavy synthetic encode of multi-MB journals can reach ~16–38ms in isolation; not observed in these final-feature scenarios.
- **No behavioral performance patch applied** beyond gated probes — only data-proven hotspots may change, and none crossed the hang bar.

## Residual

- Full WP-P1 `@Observable` / WP-P2 debounced save remain post-1.0 candidates if denser user workspaces prove hangs.
- Probes stay behind `WEIBEI_PERF=1` and can be stripped in a later cleanup if desired.
