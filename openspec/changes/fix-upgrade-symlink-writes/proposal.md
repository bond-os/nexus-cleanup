# Proposal

## Why

`upgrade` follows candidate-file symlinks and can modify a file outside the configuration
repository. That violates the command's contained-write guarantee and leaves the `init` stale-pin
warning reading files outside the target directory.

## What Changes

- Refuse `upgrade` and `upgrade --check` when a candidate path or one of its parent directories
  below the target repository is a symlink.
- Keep the refusal all-or-nothing: no candidate is read for upgrading or written before every
  candidate path has passed the symlink check.
- Prevent `init`'s stale-pin scan from reading through symlinked candidates.
- Add focused regressions for terminal symlinks, symlinked directories and check mode.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `nexus-cleanup/config-repository`: strengthen `upgrade`'s local-and-contained behavior and check
  mode so symlink traversal is refused rather than followed.

## Impact

- **Code:** `nexus-cleanup/scaffold.nu` candidate discovery, validation, upgrade and stale-pin
  inspection.
- **Tests:** `tests/test-scaffold.nu` and, if needed, CLI-level upgrade coverage.
- **Operators:** a repository containing a symlink at an `upgrade` candidate path now fails with a
  usage error instead of upgrading the symlink target.
