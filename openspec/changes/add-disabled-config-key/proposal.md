## Why

A configuration repository runs every `configs/*.yaml` file in every pipeline, so the only way
to pause one cleanup — a repository under migration, a pattern under review, an incident on the
Nexus side — is to delete or rename its file. Both lose the file's place in review history and,
for a rename, its schema mapping in the editor. Operators need to switch one file off in the
file itself, visibly, and switch it back by editing one line.

## What Changes

- **New configuration key `disabled`, boolean only.** `disabled: true` makes the run do nothing;
  `disabled: false` and an absent key are equivalent and change nothing. The key is named for
  what it stops, so it cannot be read as permission: `enabled: true` beside the refused
  `execute` key would look like a switch that allows deletion.
- **A disabled file is skipped on every run.** The CI loop, a manual `--config` run and an
  executing run alike. There is no flag that runs a disabled file anyway; to run it, edit the
  file. The tool has no notion of "in CI" and gains none.
- **The file is still validated in full.** Parsing, refused and unknown keys, types and every
  value check run as for any run, so a disabled file cannot rot unnoticed and a typo in it still
  fails the pipeline.
- **A disabled run contacts nothing.** No request is made; `--execute` and `--require-cap`
  change nothing; the exit code is 0.
- **It stays visible.** Standard error says the file is disabled and nothing was done. Standard
  output carries the report of a run that selected nothing — a valid JSON document with an empty
  record array, or the CSV header — so the CI loop's report naming and anything parsing the
  report keep working. The aggregate gains a `disabled` field, appended after `config_file`, so
  the dry-run artifacts show which files were paused.
- **The first file-only key.** `disabled` has no flag: a file pauses itself, and a command line
  that wanted to skip a file would simply not run it. `CONFIG_KEYS`, the generated schema and
  the README key table learn to describe a key with no flag.
- **AGENTS.md records the exception.** The standing rule is that no key switches the run mode.
  `disabled` can only stop a run, never widen what one does; that reasoning is written down so it
  is not later used to justify a key that does the opposite.
- **The starting configuration** written by `init` mentions the key in a comment.

Non-goals: a reason text as the value (a YAML comment carries it); a flag that overrides the
key; skipping files in `ci/run-configs.sh`, which cannot parse YAML; a new exit code.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `nexus-cleanup/config-file`: "Recognised keys" gains `disabled`; "Typed values" gives it a
  boolean type; a new requirement defines a disabled file — validated, skipped on every run, no
  request, exit 0 — and that no flag overrides it; the schema describes the key.
- `nexus-cleanup/reporting`: "Aggregate summary" gains a `disabled` field after the
  configuration file field, which is then no longer the last.
- `nexus-cleanup/config-repository`: the starting configuration file documents the key.

## Impact

- **Code**: `nexus-cleanup/config.nu` (key table row without a flag, resolved value),
  `nexus-cleanup/run.nu` (stop after validation), `nexus-cleanup/report.nu` (aggregate field),
  `nexus-cleanup.nu` (exit path).
- **Generated**: `schema/config.schema.json` via `tools/generate-config-schema.nu`; the README
  key table; `examples/<system>/configs/example.yaml` via `tools/render-examples.nu`.
- **Template**: `nexus-cleanup/templates/common/configs/example.yaml`.
- **Docs**: README "Configuration files", AGENTS.md "A configuration file can never ask for
  deletion".
- **Report consumers**: one more aggregate field, at the end; JSON readers that ignore unknown
  fields are unaffected, and CSV records are unchanged.
