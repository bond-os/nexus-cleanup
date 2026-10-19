## Context

See `proposal.md` for motivation and `specs/` for the contract. The code this change extends:

- `def main` in `nexus-cleanup.nu` declares every flag with a default (`--keep: int = 1`,
  `--pattern: string = ""`, …) and passes them all to `config resolve` as one record.
- `config resolve` already tolerates absent and `null` values — every read is
  `$overrides.<key>? | default <value>` — and owns the validation, each failure raised through
  `usage-error` so the entrypoint maps it to exit code 2.
- `report summary` builds the aggregate block, `tool_version` last; `run.nu` passes it the run's
  metadata.
- Nushell 0.115.1 parses YAML with the built-in `from yaml`; no external binary is involved.

## Goals / Non-Goals

**Goals:**

- One loading path that produces the same record `config resolve` validates today, so a value
  from the file meets exactly the validation the flag meets.
- Error messages that say where a bad value came from — `--keep` or `keep` in `configs/yum.yaml`.

Backwards compatibility of the module's commands and of the report's key order is not a goal:
signatures change where the design is simpler for it, and callers and tests are updated.

**Non-Goals:**

- Validating against the JSON Schema inside the tool. Nushell has no JSON Schema validator and
  the tool must stay free of external binaries; its own checks remain the authority.
- Reading the file anywhere except the configuration step: the plan, the API client and the
  report never see it, only the resolved record and the path.

## Decisions

### Always YAML, whatever the extension

The file is read with `open --raw` and parsed with `from yaml`, never with plain `open`. Plain
`open` chooses a parser by extension, so `configs/yum.yml`, `configs/yum.conf` and a file with no
extension would each behave differently, and an unknown extension returns a string that then
fails as "not a mapping" with a confusing message. JSON is a subset of YAML, so a JSON file works
without being a promise.

*Alternative considered:* dispatch on extension and accept TOML and NUON too. Rejected: three
formats to document and test for no operator benefit.

### Defaults live only in `config resolve`

`def main` drops every default: `--keep: int`, `--pattern: string` and so on are `null` when not
passed. That is the only way to tell "not passed" from "passed with the default value", which
layering needs — with `--keep: int = 1`, a file's `keep: 3` could never be applied because the
flag always arrives as `1`. `config resolve` already supplies every default, so this moves no
logic, it removes a duplicate. Each flag's comment states its default so `--help` still shows it.

Switches (`--execute`, `--fail-on-skip`) stay switches: Nushell passes `false` when absent, so a
switch can only turn a setting on. `fail-on-skip` is therefore `flag or file`. `execute` never
reads the file at all.

### Loading is separate from resolving

A new `config load <path>` reads the file and returns
`{path: <as given>, values: <record keyed by internal names>, origin: <file key per internal name>}`.
It owns everything specific to the file: parse errors, the top level being a mapping, forbidden
keys, unknown keys, and type checks including `timeout` → `into duration`. It does not apply
ranges or regex checks.

`config resolve` gains an optional `--file: record` (the output of `config load`) and layers per
setting: flag value if not `null`, else environment for `url`/`username`, else the file value,
else the default. Every existing validation then runs once on the merged value. When a
validation fails, the message names the setting by its source: the flag spelling if the value
came from a flag, `'<key>' in <path>` if it came from the file.

*Alternative considered:* merging the file into the flag record in the entrypoint and calling
`config resolve` unchanged. Rejected: the merged record would no longer know where a bad value
came from, and the error would name `--keep` for a value the operator wrote in a file.

### One table drives keys, types and mapping

A single constant lists each file key with its internal name and its type. Unknown-key
detection, type checks and the README table derive from it, so adding a flag later means one
row, not three edits that can drift. `execute` and `password` sit in a separate refused-keys
table with their own messages; a refused key is reported before unknown keys, so `execute: true`
gets the specific message rather than "unknown key".

Each row also carries the constraints the schema needs — `minimum` for the counts, the 0–1 range
for the share, the `format` and `version-scheme` enums taken from `FORMATS` and `SCHEMES`, a
duration pattern, an `http(s)` URL pattern without user information, and a lookahead pattern
requiring both named groups in `from-path` — and a one-line description that the schema and the
README both use.

### The JSON Schema is generated from the key table

`tools/generate-config-schema.nu` turns the key table and the refused-keys table into
`schema/config.schema.json` (draft 2020-12, `additionalProperties: false`). Refused keys appear as
properties whose schema is `{"not": {}}` — equivalent to `false`, which cannot carry one — with a description stating why and what to use instead, so an
editor explains the refusal rather than only reporting an unknown key. A test regenerates the
schema in memory and fails if it differs from the committed file, so a key added to the tool
without regenerating cannot reach `main`.

The generator lives in `tools/`, development only, like the fixture recorder. The schema is
emitted with sorted keys and fixed indentation so regeneration is byte-stable.

*Alternative considered:* a hand-written schema with a test comparing its key set to the table.
Rejected: it catches a missing key but not a drifted type or range, and every constraint would
still be written twice.

*Alternative considered:* a `--print-config-schema` flag on the tool. Rejected: it would add a
runtime surface for something only editors and CI consume, and the schema is already fixed per
release.

### Where a rule cannot be expressed exactly, the schema is looser

The schema is an aid; the tool decides. Whether a regex compiles under Nushell's engine, or
whether a duration string is one `into duration` accepts in every spelling, cannot be stated
exactly in JSON Schema's ECMA-262 patterns. In each such case the pattern admits a superset of
what the tool accepts, so a valid file is never flagged in the editor — a schema that rejects
working files teaches operators to ignore it.

### The schema is versioned by the release tag, not published elsewhere

Operators reference it with a YAML language server modeline pinned to a tag:
`# yaml-language-server: $schema=https://raw.githubusercontent.com/bond-os/nexus-cleanup/vX.Y.Z/schema/config.schema.json`.
Release tags are write-once, so a pinned schema never moves, and it matches the image version
the pipeline pins. A JSON file can carry the same URL in a top-level `$schema` key, which is why
the tool accepts and ignores that key.

*Alternative considered:* submitting the schema to SchemaStore. Rejected: SchemaStore serves one
floating schema per file pattern, which is the `latest` tag problem the release design already
refuses — a config validated against a newer schema than the pinned tool accepts.

*Alternative considered:* copying the schema into the image. Rejected: nothing in the image
reads it, and the `.dockerignore` allow-list stays limited to the tool and its launcher.

### CI validates example files with ajv-cli

A `config-schema` job in `tests.yml` — its own job, because the `test` job's Nushell container
has no Node — runs `ajv-cli` in strict mode through `npx`, at an exact version pinned in `env:`
as `commits.yml` pins commitlint (no `ajv-formats`: the schema uses no `format` keyword), over
every configuration file under `examples/` and
the README's worked file (extracted to `examples/` so it is a real file rather than a snippet).
This exercises the schema with an independent validator: the generator test proves the
committed file is current, ajv proves it is a valid schema that accepts the files the project
ships. It belongs to maintenance automation; the hermetic Nushell suite does not depend on it.

### The selection is one unit

`repositories` and `pattern` are resolved together: if the command line supplied either, both
come from the command line; otherwise both come from the file. Merging them per key would let a
file `pattern: "yum-*"` combine with a command-line name, and since names take precedence in
`api select-proxies`, the pattern would be silently dropped anyway — but only after the operator
had read the file and assumed it applied.

### The report records the path as given

`config_file` holds the option's argument verbatim, not an absolute path. An absolute path would
expose the runner's directory layout and make two otherwise identical reports from different
runners differ. The field is appended after `tool_version`; the reporting delta moves the "last
field" assertion accordingly.

### `--require-cap` keeps the pipelines' cap guard with per-file caps

The example execute jobs used to refuse to run without a pipeline `MAX_DELETIONS` and pass it as
`--max-deletions`. With a file per target, each file carries its own cap, and a pipeline-wide
flag would override all of them (flag > file). The pipeline cannot check the files itself — it
has no YAML reader — so the tool does: `--require-cap` makes a run whose resolved configuration
has neither `max-deletions` nor `max-deletion-share` a usage error.

It applies to dry runs too, so the loop passes it to every run and a file missing its cap fails
in the scheduled dry run rather than when someone presses execute. It is a flag only, not a file
key: the guard belongs to the pipeline, and a file could only ever turn it on.

*Alternatives considered:* a pipeline-wide cap passed to every run (loses per-file caps), and
caps documented but unenforced (weaker than the guard the examples had).

### Example pipelines run one job that loops over the configuration directory

Each example pipeline has one dry-run job and one manual execute job, and each job loops over
`configs/*.yaml` (the directory is a pipeline variable, `configs` by default) in sorted order,
calling the tool once per file. Adding a configuration file therefore needs no pipeline edit.

- **The loop carries on past a failing file.** One broken configuration must not hide the
  reports of the others. Each run's exit code is recorded and the job ends with an aggregate:
  any code other than 0 and 4 fails the job with the first such code; otherwise 4 if any file
  had skipped groups; otherwise 0. Pipelines keep treating 4 as a warning.
- **An empty directory is an error.** A `sh` glob that matches nothing expands to itself, so the
  loop checks for that explicitly rather than succeeding having run nothing.
- **One report per file**, `reports/<basename>.<mode>.json` and `reports/<basename>.<mode>.summary.json` (mode `dry-run` or `execute`), kept
  as artifacts, so a reviewer reads each configuration's plan on its own.
- **The execute job runs the same loop with `--execute`** from the same commit, so it covers
  exactly the files the dry run reported on.

The jobs need the repository checked out, so `GIT_STRATEGY: none` is dropped — the checkout
lands in `/work`, which the image keeps empty for exactly this. The existing `resource_group`
keeps runs against one Nexus serial. The loop is one POSIX `sh` script,
`examples/ci/run-configs.sh`, that every example pipeline calls (`sh examples/ci/run-configs.sh`,
and with `--execute` in the execute job), so it is written and tested once rather than in four CI
dialects. It is glue, not a tool feature: one file stays one run, and the tool gains no multi-run
mode.

*Alternative considered:* one job per file through `parallel: matrix:` (GitLab) or a matrix
strategy (Forgejo). Rejected: the matrix lists every file, so adding a configuration means
editing the pipeline as well, and the per-job split buys nothing a per-file report does not.

## Risks / Trade-offs

- [YAML coerces unquoted scalars — `on`/`off`, leading zeros, `1e3`] → Typed values are the
  backstop: a coercion that changes the type is a usage error, not a silent default. The README
  recommends quoting patterns and globs, single-quoting regexes so backslashes survive.
- [`--help` loses its "default:" annotations when defaults leave `def main`] → Each flag's
  comment states its default; a CLI test asserts the help text still mentions them.
- [The file's `url` is silently overridden by a CI-wide `NEXUS_URL`] → Deliberate: the
  environment is how one set of files is reused against staging and production. A diagnostic on
  stderr names the source of the URL in effect when the file also set one.

## Migration Plan

Additive. Runs without `--config` behave as before. Rollback is pinning the previous image tag.
