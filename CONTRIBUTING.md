# Contributing to WeiBei

Thank you for helping improve WeiBei.

## Before opening a pull request

1. Open or reference an issue that explains the learner problem and the intended
   scope.
2. Keep each pull request focused on one change.
3. Run the relevant checks:

   ```bash
   ./script/build_and_run.sh check
   ```

4. Describe what changed, what was intentionally left out, and which checks
   passed.
5. Do not commit course files, notes, credentials, model outputs containing
   private data, or material you do not have the right to distribute.

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
