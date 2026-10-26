## Context

See proposal.md for why. What exists today:

- `CONFIG_KEYS` in `config.nu` has one row per file key — key, resolved field, type, schema
  constraints, description — and every key is also a flag. The schema generator, the README key
  table (between `config-keys` markers, checked by `tests/test-config-file.nu`) and
  `config load`'s type checks all read it.
- The entrypoint loads the file, calls `config resolve` (every check that precedes a request,
  `--require-cap` included), builds the API client (which sends nothing), then calls
  `cleanup run` and emits its report with `cleanup emit`.
- `report summary` builds the aggregate from records and a run record; `config_file` is its
  last field. An empty record list already yields a valid, zeroed report.
- `ci/run-configs.sh` names each report from its first line and treats exit 0 as success.

## Goals / Non-Goals

**Goals:**

- A disabled file passes through exactly the same validation as an enabled one and diverges
  only where the first request would be sent.
- No new mechanism in the entrypoint, the loop or the report encoder.

**Non-Goals:**

- Any notion of where the tool runs (CI or not).

## Decisions

### The key table gains rows without a flag

A row may declare that it has no flag; `disabled` is the first. The generator and type checks
treat it like any other boolean row. The README table shows `—` in its Flag column, and the flag
layering in `config resolve` is skipped for it: its value comes from the file or is `false`.

Alternative: a separate `FILE_ONLY_KEYS` list. Rejected because AGENTS.md requires one key
table driving mapping, types, schema and README; a second list is the "three places" that rule
exists to prevent.

### The decision is made in `cleanup run`, before anything else it does

`cleanup run` returns at its first line for a disabled configuration: it writes the stderr note
and returns the report of no records with `disabled: true` and exit code 0. The entrypoint is
unchanged and still emits whatever `cleanup run` returns, so the report, `--summary-out` and the
format all follow the existing path. The client exists but has sent nothing, which a stubbed
fetch in the tests can assert.

Alternatives: branching in the entrypoint would put a decision in a file that AGENTS.md keeps to
"flags → module calls → exit code"; branching in `config resolve` would make a validation
function decide the run's outcome.

### Validation is not shortened

Because the branch sits after `config resolve`, everything already checked — unknown and
refused keys, types, ranges, patterns, the URL, a missing selection and `--require-cap` — still
applies. This is deliberate: a file is usually disabled for a while and re-enabled later, and it
must not come back broken. Disabling a file that does not validate is not supported; such a file
already fails the pipeline and is fixed or removed.

### The aggregate always carries `disabled`

The field is appended after `config_file` and is `false` on every enabled run, so consumers see
one shape. It describes the run, not the key: a run without a file reports `false`.

### The run's mode is reported as requested

A disabled file run with `--execute` reports mode `execute` with zero deletions. The mode says
what the operator asked for and `disabled` says why nothing happened; rewriting the mode would
hide that someone tried to execute a paused file.

## Risks / Trade-offs

- [A paused file is forgotten and stays paused] → The note on stderr in every pipeline run and
  `disabled: true` in each kept summary make it visible; nothing more is enforced.
- [A consumer that asserted `config_file` is the last aggregate field] → The spec allowed
  appending; the change is noted in the changelog through the `feat` commit.
- [`enabled: false` typed from habit] → Refused as an unknown key, with the list of known keys
  that includes `disabled`.
