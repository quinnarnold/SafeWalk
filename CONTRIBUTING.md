# Contributing

Thank you for contributing to SafeWalk.

## Before opening a pull request

1. Create a focused branch.
2. Do not add raw incident data, generated city artifacts, credentials, or
   machine-specific files.
3. Add or update tests for behavior changes.
4. Run the checks documented in the root README.
5. Update documentation when configuration, data sources, output schemas,
   privacy behavior, or safety claims change.

Keep changes narrow and preserve the distinction between source code and
third-party/generated data. New cities must include a public, documented input
source; normalization code; reproducible command; attribution/terms entry; and
tests or a small non-sensitive fixture.

For security issues, follow `SECURITY.md` instead of filing a public issue.
