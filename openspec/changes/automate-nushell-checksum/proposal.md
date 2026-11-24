# Proposal

## Why

Every Nushell update intentionally makes the required `nushell-checksum` check fail because
Renovate moves `NU_VERSION` but cannot maintain the tarball's SHA-256 in the Forgejo template.
The resulting copy, amend and rerun sequence is deterministic but currently halts every
Renovate Nushell pull request until a maintainer performs it manually.

## What Changes

- Add a maintenance workflow that reacts to a failed `tests` workflow for a same-repository
  `renovate/nushell` pull request.
- Validate that the pull request is the expected Renovate Nushell update, that the failure is
  specifically the checksum mismatch, and that every changed file is in the existing Nushell
  pin allowlist before taking action.
- Download the declared Nushell release asset, calculate its checksum, update the Forgejo
  template and rendered example, and amend the existing update commit rather than adding a
  second release-visible commit.
- Push the amended Renovate branch and explicitly rerun the tests workflow because pushes made
  with the workflow token do not start another pull-request workflow automatically.
- Keep the checksum job and its required-check behavior intact; the automation never bypasses,
  disables or merges a failing pull request.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `nexus-cleanup/distribution`: Nushell dependency updates automatically repair the verified
  Forgejo tarball checksum while preserving the single release-visible commit and all required
  merge gates.

## Impact

- A new trusted GitHub Actions maintenance workflow and narrowly scoped supporting script.
- Repository workflow permissions for only the repair job (`contents: write` and
  `actions: write`), with no pull-request approval or merge permission.
- OpenSpec distribution requirements, workflow documentation in `AGENTS.md`, and focused
  automation tests covering eligibility and refusal conditions.
