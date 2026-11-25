# Tasks

## 1. Checksum repair script

- [x] 1.1 Add a maintenance script that strictly parses the Forgejo template and example,
  downloads their declared x86_64 musl release asset, calculates SHA-256, and updates only a
  stale `NU_SHA256` pair; verify it with hermetic Nushell tests using a local download stub.
- [x] 1.2 Add refusal coverage for matching checksums, malformed or duplicate values, different
  versions and different checksums; verify each case leaves the input files unchanged.

## 2. Trusted repair workflow

- [x] 2.1 Add a `workflow_run` workflow for failed `tests` runs that validates the same-repository
  `renovate/nushell` pull request, failed `nushell-checksum` job, author, exact head revision and
  changed-file allowlist; verify the workflow's trigger and eligibility guards with focused
  tests.
- [x] 2.2 Run the repair script from a default-branch checkout while treating a full-history
  pull-request checkout as data, amend only the two checksum files without removing the
  original parent, push with an exact-SHA `--force-with-lease`, and dispatch `tests.yml`; verify
  staged-file, ancestry, commit and concurrency safeguards with focused tests.
- [x] 2.3 Update `AGENTS.md` and the Nushell Renovate pull-request note to describe the automatic
  repair, its refusal behavior and the manual fallback; verify the rendered guidance names the
  preserved check and single-commit requirement.

## 3. Integration verification

- [x] 3.1 Run `nu tests/run-tests.nu` in the pinned Nushell image and verify the complete suite
  passes.
- [x] 3.2 Run the repository's workflow syntax/static checks and `openspec validate
  automate-nushell-checksum --strict`; verify no validation or lint error remains.

## Workflow follow-up

- Merge this change before relying on the new default-branch workflow.
- Archive the OpenSpec change after the implementation has been verified.
