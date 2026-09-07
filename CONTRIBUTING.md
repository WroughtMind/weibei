# Contributing to WeiBei

Thank you for helping improve WeiBei.

## Before opening a pull request

1. Explain the learner problem and keep each pull request focused on one change.
   Link an existing issue when relevant; a separate issue is not required.
2. Validate the affected output: website scripts, assets, and relevant browser
   behavior for website changes; syntax, types, and behavior for tools; compilation
   and affected checks for App code; artifact checks for packaging inputs.
   Documentation and PR templates need content, links, and `git diff --check` only.
   Website, tool, and documentation changes do not require an App build or package.
   Combine the relevant checks for mixed changes. Before merging, bring the branch
   up to date and pass the required checks against its combination with the latest
   `main`; do not disable this protection. App checks run before merge without a
   duplicate post-merge run. Full candidate builds belong to an explicit App
   integration or candidate-acceptance task, not every merge.
3. Describe the problem solved, verification performed, and remaining risks.
   Record one focused real-App smoke check for user-visible App changes. Include
   a real-App screenshot for substantial layout changes, new screens, or visual
   bug fixes; add before screenshots only when comparison helps review. Do not
   require screenshots for minor copy, style, or behavior-only changes.
4. Include targeted evidence for data safety, permissions, performance, or
   packaging when affected; do not fill unrelated verification sections.
5. Do not commit course files, notes, credentials, model outputs containing
   private data, or material you do not have the right to distribute. Screenshots
   must not expose private materials or credentials.

## Contribution license

Unless stated otherwise, contributions are accepted under the MIT License used
by this repository. By submitting a contribution, you confirm that you have the
right to provide it under those terms.

## Product principles

- Keep the learner in control of note and learning-state changes.
- Preserve source provenance and expose incomplete indexing honestly.
- Prefer plain, readable answers; use interactive forms only when they improve
  understanding.
- Do not add unrestricted file, terminal, credential, or network access to the
  Agent.
