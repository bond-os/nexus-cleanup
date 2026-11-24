# Proposal

## Why

An operator cannot add a file to a repository `init` already wrote: re-running `init` refuses
because files exist, and `--force` overwrites all of them, including the pipeline holding the
operator's Nexus URL. So a template added by a release, an editor chosen later, or a corrected
`run-configs.sh` can only be picked up by hand.

## What Changes

- `init --skip-existing` writes the planned files that are missing, keeps every file that exists
  and lists what it kept. Combined with `--force` it is a usage error.
- `init --only <group>`, repeatable, narrows a run to named groups of the selected files:
  `pipeline`, `runner`, `base`, `example`, `editor`, `env`. `--ci` stays required and the selection
  flags keep describing the whole repository. `--only editor --force` therefore refreshes one group
  and leaves the pipeline alone.
- `init` warns on stderr when files it did not write pin another version, and advises `upgrade`.
- `init --check` and `upgrade --check` report on stdout what the same command would do and write
  nothing. There is deliberately no `--dry-run` spelling: the cleanup itself records that it has
  no such flag.
- **BREAKING** `configs/example.yaml` ships with `disabled: true`, as a reference to copy rather
  than a file to edit. It can stay beside real configurations, so `--skip-existing` restoring it is
  harmless. An unedited repository whose URL is set now passes doing nothing, where it used to fail
  naming `replace-me`. This is a deliberate trade, and `run-configs.sh` gains no guard against it.

Out of scope: a line-by-line diff (Nushell has no diff command, so it would be new code to write
and test), and merging into an existing file, which `init` has never done.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `nexus-cleanup/config-repository`: existing files can be kept, a run can be narrowed to groups,
  stale pins are named, `init` and `upgrade` gain a check mode, and the starting configuration file
  ships disabled. That last part removes the requirement "Starting configuration file" and adds
  "Reference configuration file", because its "fails loudly" scenario no longer holds.

## Impact

- **Code:** `nexus-cleanup/scaffold.nu` (plan groups, write modes, argument parsing, help, pin
  check, check reports), the `init` and `upgrade` commands in `nexus-cleanup.nu`.
- **Templates:** `common/configs/example.yaml`, and through it the generated
  `examples/<system>/configs/example.yaml`.
- **Tests:** `tests/test-scaffold.nu`, including the tests that an unedited example fails loudly.
- **Docs:** `README.md` (first steps, upgrading) and `AGENTS.md` (the `replace-me` rationale, the
  new standing decisions).
- **Operators:** `upgrade` does not touch an existing `example.yaml`, so existing repositories keep
  theirs until they refresh it. Release notes must describe the new example flow.
