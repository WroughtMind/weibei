# Security policy

## Supported version

WeiBei is currently a pre-release project. Security fixes are applied to the
latest commit on the main development line; older commits and local builds are
not maintained as separate supported releases.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose course
content, credentials, local files, or a user's machine.

Use GitHub's private vulnerability reporting or a private security advisory for
this repository. Include:

- the affected commit and macOS version;
- the smallest reproducible steps;
- the security impact;
- whether credentials or private course data were exposed;
- any proposed mitigation.

Do not include real credentials or private course documents in the report.

## Security boundary

WeiBei's Agent receives bounded snapshots selected by the host application. It
must not receive unrestricted file, terminal, credential, or network access.
Reports that cross this boundary are treated as high priority.
