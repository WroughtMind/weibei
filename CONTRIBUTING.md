# Contributing to WeiBei

Thank you for helping improve WeiBei.

## Before opening a pull request

1. Open or reference an issue that explains the learner problem and the intended
   scope.
2. Keep each pull request focused on one change.
3. Run the relevant checks:

   ```bash
   make check
   make verify
   ```

4. Describe what changed, what was intentionally left out, and which checks
   passed.
5. Do not commit course files, notes, credentials, model outputs containing
   private data, or material you do not have the right to distribute.

## Contribution license

Contributions are accepted under the Contributor License Agreement in
[`CLA.md`](CLA.md). Add this exact statement to your first pull request:

> I have read and agree to the WeiBei Contributor License Agreement.

This keeps the public project under `AGPL-3.0-only` while allowing the
maintainer to offer separate commercial terms without taking ownership of a
contributor's work.

Pull requests that do not include this agreement will not be merged.

## Product principles

- Keep the learner in control of note and learning-state changes.
- Preserve source provenance and expose incomplete indexing honestly.
- Prefer plain, readable answers; use interactive forms only when they improve
  understanding.
- Do not add unrestricted file, terminal, credential, or network access to the
  Agent.
