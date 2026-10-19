## Why

Operators want one private pipeline that cleans several repositories, each with its own
settings — a yum proxy at `--keep 2`, a raw build repository with a `--from-path` pattern and
the `date` scheme at `--keep 14`. Today every setting is a flag, so each variant means another
hand-edited job script, and the regexes that matter most live in shell quoting inside CI YAML
where they are hardest to read and review.

A configuration file per target lets the pipeline stay generic — it is pointed at
`configs/<target>.yaml` — while each file is an ordinary, reviewable record of exactly what a run
will do.

## What Changes

- **`--config <path>`** reads a YAML file whose keys are the existing flag names, spelled
  exactly as on the command line (`keep`, `from-path`, `max-deletions`, `repositories`, …). One
  file describes one run; the pipeline invokes the tool once per file.
- **Layering.** A flag overrides the file. For connection settings the environment sits between
  them: flag > environment > file > default. For every other setting: flag > file > default. A
  repository selection given on the command line (names or `--pattern`) replaces the file's
  selection as a whole rather than merging with it.
- **Safety keys are not file settings.** `execute` in a file is a usage error — deletion stays
  something only the `--execute` flag can ask for. `password` in a file is a usage error —
  credentials stay in the environment or CI secrets, never in a repository.
- **Strict parsing.** An unknown key, a value of the wrong type, a missing or unreadable file,
  or a document that is not a mapping is a usage error naming the file and the key, raised
  before any request. A misspelt `keeep: 3` must not silently fall back to `keep: 1`.
- **`--require-cap`** refuses a run, dry or executing, whose resolved configuration sets no
  deletion cap. The example loop passes it to every run, keeping the cap guard the example
  pipelines enforced before while letting each file carry its own cap.
- **The report names its configuration.** The aggregate block gains a `config_file` field,
  appended after `tool_version`, holding the path given to `--config` (empty without one).
- **A JSON Schema for the file**, `schema/config.schema.json`, so editors flag a misspelt or
  refused key while the file is being written rather than when a pipeline runs. It is generated
  from the tool's own key table, committed, and referenced by a URL pinned to a release tag, so
  the schema an operator uses always matches the image version they pin. A top-level `$schema`
  key is accepted and ignored so that files can point at it. The tool keeps its own validation
  as the authority; the schema is an aid.
- **Examples** show a private pipeline repository holding several configuration files, with one
  job that loops over `configs/*.yaml`, so adding a configuration needs no pipeline edit. CI
  validates every example configuration file against the schema.

Non-goals: several runs in one file, per-repository settings inside one run, an environment
variable naming the file, includes or inheritance between files, and configuration formats
other than YAML (JSON documents parse as YAML and are accepted as a side effect, not a
feature).

## Capabilities

### New Capabilities
- `nexus-cleanup/config-file`: loading a run's settings from a YAML file — which keys exist,
  which are refused, how values are typed and validated, how the file layers under flags and
  the environment, and the published schema describing it.

### Modified Capabilities
- `nexus-cleanup/cli`: configuration precedence gains the file layer; the dry-run requirement
  states that a configuration file cannot imply execution; the tool accepts `--config`.
- `nexus-cleanup/reporting`: the aggregate block gains `config_file` after `tool_version`, so the
  tool version is no longer the last aggregate field.

## Impact

- **Code**: `config.nu` (file loading, key mapping, type checks, layering), the entrypoint (flag
  defaults move out of `def main` so an absent flag can be told from one passed with its default
  value; `--config` added), `report.nu` (`config_file`), `run.nu` (passing the path to the
  summary).
- **Tests**: a new `tests/test-config-file.nu`; extensions to `test-config.nu`, `test-cli.nu`
  and `test-report.nu`; YAML fixtures under `tests/fixtures/config/`; a test that the committed
  schema equals the generator's output.
- **Schema**: `schema/config.schema.json` (committed, generated) and
  `tools/generate-config-schema.nu` (development only, like `tools/record-fixtures.nu`). Neither
  reaches the image.
- **CI**: a step in `tests.yml` validating `examples/**/*.yaml` configuration files and the
  README's worked file with `ajv-cli`, run through `npx` at pinned versions as commitlint is.
  Maintenance automation only; nothing from it becomes a runtime dependency.
- **Compatibility**: not preserved deliberately. Runs without `--config` decide and delete
  exactly as before; the module's command signatures and the aggregate's key order may change.
- **Runtime**: YAML is parsed by Nushell's built-in `from yaml`; no new dependency.
- **Docs**: `README.md` (configuration file section, layering table, example file, the schema
  modeline), `examples/` (multi-file pipeline), `AGENTS.md` (why `execute` and `password` are
  refused in the file; the schema is generated, never hand-edited, and versioned by tag).
