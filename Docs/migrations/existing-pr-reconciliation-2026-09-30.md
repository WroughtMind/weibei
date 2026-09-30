# Existing pull-request reconciliation

Verified on 2026-09-30 against migrated Codeberg main `c98803055954d239f93644899122fae579659db7` and archived GitHub main `97c97800d8ced9e3a16900ddb12193591b958ad5`. This is a read-only content/history review. No PRs were closed, branches changed, or remote writes made.

## Decision summary

Four older GitHub PRs are obsolete: **#506, #510 and #511 were already incorporated through exact-equivalent Codeberg squash patches; #509 was deliberately superseded by the corrected DeepSeek implementation. Do not merge these old branches again.** Keep #485 as the one genuine unfinished older PR: it is the exact same head as open Codeberg #16 and needs realignment with current main.

| Existing GitHub PR | Codeberg counterpart | Content finding | Current merge simulation | Recommended action |
|---|---|---|---|---|
| [#506](https://github.com/WroughtMind/weibei/pull/506), search-error reporting, head `26bf0a91` | [#4](https://codeberg.org/WroughtMind/weibei/pulls/4), squash `e19c0bc8` | Entire 11-file combined patch included exactly; even the complete branch and squash trees match | One stale-branch conflict in `NativeHTTPByteStream.swift` after newer error handling | Treat as already incorporated; propose closure with #4/main evidence, without merging again |
| [#509](https://github.com/WroughtMind/weibei/pull/509), DeepSeek, head `73f535b1` | [#1](https://codeberg.org/WroughtMind/weibei/pulls/1), updated source head `d45799f1`, squash `948f092a` | Old choices were superseded: `deepseek-v4-flash`/search enabled became `deepseek-flash`/search disabled; corrected routing and assertions are present | Conflicts in routing and runtime tests | Treat as superseded; preserve the corrected implementation and propose closure with explanation |
| [#510](https://github.com/WroughtMind/weibei/pull/510), first-answer source checks, head `7cbd7b60` | [#2](https://codeberg.org/WroughtMind/weibei/pulls/2), squash `f4b99f47` | Entire one-file patch included exactly; original rules remain in main | Clean merge producing exactly the existing main tree, a content no-op | Treat as already incorporated; propose closure with #2/main evidence |
| [#511](https://github.com/WroughtMind/weibei/pull/511), nine task skills, head `0a345e8f` | [#3](https://codeberg.org/WroughtMind/weibei/pulls/3), squash `8077d120` | Entire 43-file combined patch included exactly; 42 original touched files unchanged since squash | One stale-branch conflict in `NativeAgentTools.swift` after newer presentation/error handling | Treat as already incorporated; propose closure with #3/main evidence |
| [#485](https://github.com/WroughtMind/weibei/pull/485), whiteboard classroom, head `3f12c866` | [#16](https://codeberg.org/WroughtMind/weibei/pulls/16), still open with the **identical full SHA** | Genuine retained unfinished work; 17 branch-only commits, 78 main-only commits, 107 branch-diff files | Eight conflict paths, listed below | Retain the existing PR; resolve/rebuild on current main only with appropriate authorization |

Recommendations are decisions for the owner; none were executed. GitHub titles and original commit ancestry alone are unreliable here: squash merging changes commit identity, and titles can lag later branch updates.

## Exact inclusion evidence

Combined branch diffs were computed from their actual common base with archived GitHub main. Squash diffs were computed from each squash commit's first parent. Stable patch IDs use the repository's normal/default path quoting.

| PR | Original combined diff | Codeberg squash diff | Matching stable patch ID |
|---|---|---|---|
| #506 | `97c97800..26bf0a91` | `e19c0bc8^..e19c0bc8` | `77b17e8b098839c371e82aad4cdef8101f699603` |
| #510 | `97c97800..7cbd7b60` | `f4b99f47^..f4b99f47` | `2d042e5d4e6c6f6a27810453be9e68392147aa95` |
| #511 | `97c97800..0a345e8f` | `8077d120^..8077d120` | `57be81fcfaa98bc882ae6890fea70dc969fda4e0` |

All four counterpart squash commits (`e19c0bc8`, `948f092a`, `f4b99f47`, `8077d120`) are ancestors of main `c9880305`. This establishes incorporation even though the original feature-branch commit SHAs are not ancestors.

### #506: included, then evolved

The exact 11-file patch covers the provider implementations, `NativeAgentEvents.swift`, `NativeAgentLoop.swift`, `NativeAgentPrompt.swift`, `StudyAgentRuntime.swift`, self-checks, and `Tests/WeiBeiSafetyTests/NativeProviderSearchFailureTests.swift`. The latter and `NativeAgentPrompt.swift` remain byte-identical to the squash versions.

Nine touched files have later main changes. In particular, `1f82741c` added structured quota/rate-limit/error-body handling and separate connection/idle timeouts in `Providers/NativeHTTPByteStream.swift`. Main still explicitly classifies rejected search as `web_search_unsupported`. The old branch's conflict is explained by that later evolution, not by missing migration content.

### #509: corrected implementation supersedes the old proposal

Old GitHub head `73f535b1` changes only routing and one assertion, choosing `deepseek-v4-flash`, retaining `.responsesTool`, and labeling search as awaiting verification. Source commit `cf444740` subsequently records the probe-driven correction to `deepseek-flash`, `.none`, and a note that the server does not execute `web_search`.

The updated source's code-only diff and squash #1's code-only diff are exactly equivalent across:

- `Sources/WeiBeiCore/NativeAgentRuntime/NativeProviderRouting.swift`
- `Sources/WeiBeiSelfCheck/NativeAgentSelfChecks.swift`
- `Tests/WeiBeiSafetyTests/NativeAgentRuntimeTests.swift`

Their stable patch ID is `2886ba43301bfa2ec732ae0b78296907d42c6cd6`. Current main retains the corrected routing verbatim and the assertions at runtime-test lines 1786–1788. Merging the old GitHub branch would attempt to revive the superseded values.

Narrow documentation caveat: the latest source head `d45799f1` also has a newer paragraph in `Docs/plans/2026-09-18-DeepSeek接入与首答事实核实-接手计划.md` describing a later combined-runtime verification. That paragraph is not in squash/main. It is preserved in the migrated source branch, and was never part of old GitHub #509's two-file patch. Therefore the **corrected code** is equivalent, not the complete latest source-branch tree.

### #510 and #511: both fully included

#510's added rules remain in `Sources/WeiBeiCore/AgentResources/system.md`, including timing/statistical-scope checks, source-conflict handling, narrowing unsupported conclusions, and treating a user's challenge as reason to recheck rather than automatic proof of error. The only subsequent change to that file is #511's additive skill-loading section.

#511 includes all nine skills (`close-reading`, `course-search`, `discussion-recall`, `learning-memory`, `note-writing`, `practice-feedback`, `source-synthesis`, `web-reading`, `web-research`), their manifests/references, registration, progressive loading/runtime changes and `NativeSkillDisclosureTests.swift`. Of its 43 original touched files, only `NativeAgentTools.swift` subsequently changed. Its loader/resource implementation remains intact; the later edits are error-result sanitization (`1f82741c`) and localized activity presentation (`fe0173c6`). These edits explain the stale branch's merge conflict.

## Retained open Codeberg PRs

Safe local `git merge-tree --write-tree --name-only` simulations used fixed main `c9880305` and the archived PR heads. They do not modify worktrees, branch refs, or remotes.

| Codeberg PR | Preserved GitHub PR | Head | Branch-only commits | Result against main |
|---|---|---|---:|---|
| [#44](https://codeberg.org/WroughtMind/weibei/pulls/44) | [#513](https://github.com/WroughtMind/weibei/pull/513) | `9de7568b` | 7 | Clean; main is an ancestor |
| [#45](https://codeberg.org/WroughtMind/weibei/pulls/45) | [#514](https://github.com/WroughtMind/weibei/pull/514) | `9d8a1f58` | 1 | Clean; main is an ancestor |
| [#46](https://codeberg.org/WroughtMind/weibei/pulls/46) | [#515](https://github.com/WroughtMind/weibei/pull/515) | `d68569ee` | 11 | Clean; main is an ancestor |
| [#47](https://codeberg.org/WroughtMind/weibei/pulls/47) | [#516](https://github.com/WroughtMind/weibei/pull/516) | `3c88ebd6` | 2 | Clean; main is an ancestor |
| [#48](https://codeberg.org/WroughtMind/weibei/pulls/48) | [#517](https://github.com/WroughtMind/weibei/pull/517) | `420007ab` | 5 | Clean; main is an ancestor |
| [#49](https://codeberg.org/WroughtMind/weibei/pulls/49) | [#518](https://github.com/WroughtMind/weibei/pull/518) | `a71f3245` | 44 | Clean; main is an ancestor |
| [#50](https://codeberg.org/WroughtMind/weibei/pulls/50) | [#519](https://github.com/WroughtMind/weibei/pull/519) | `14ed00a9` | 1 | Clean; main is an ancestor |
| [#16](https://codeberg.org/WroughtMind/weibei/pulls/16) | [#485](https://github.com/WroughtMind/weibei/pull/485) | `3f12c866` | 17 | Conflicts; main has advanced by 78 commits from common base |

The exact eight #485/#16 conflict paths are:

1. `Sources/WeiBei/Resources/Editor/editor-entry.js`
2. `Sources/WeiBei/Resources/Editor/editor-resources.json`
3. `Sources/WeiBei/Resources/Editor/viewer-entry.js`
4. `Sources/WeiBei/Resources/genui.html`
5. `Sources/WeiBei/Resources/three.js`
6. `THIRD_PARTY_NOTICES.md`
7. `script/build_and_run.sh`
8. `script/build_genui.mjs`

Preserve the authored whiteboard/read-aloud work; generated assets should be regenerated using the repository's build workflow after source realignment, rather than choosing an entire older side wholesale. That is a proposed follow-on engineering task, not a change made by this review.

## Verification limits

This review verifies archived PR identity, Git object ancestry, exact combined-patch equivalence, selected tracked-file contents and merge conflict simulations. It did **not** run builds, test suites, fresh model probes, native macOS acceptance, or remote CI checks. A clean merge simulation is not a test pass or release approval. The seven new retained branches were checked individually against main, not pairwise or as a proposed sequential integration. Recheck compatibility and tests at the actual merge point.
