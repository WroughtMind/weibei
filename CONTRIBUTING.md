# Contributing to WeiBei

Thank you for helping improve WeiBei.

## Before opening a pull request

1. Explain the learner problem and keep each pull request focused on one change.
   Link an existing issue when relevant; a separate issue is not required.
2. For code changes, compile and run the checks relevant to the affected behavior.
   For documentation or PR-template-only changes, review content and links and
   run `git diff --check`; no App build or package is required. Wait for the CI
   checks triggered by the change to pass.
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
