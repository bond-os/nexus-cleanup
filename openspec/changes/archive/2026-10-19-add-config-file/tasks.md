## 1. Loading the file

- [x] 1.1 Write failing tests in `tests/test-config-file.nu` for `config load` over YAML fixtures in `tests/fixtures/config/`: every recognised key maps to its internal name with the right type; `timeout: 2min` becomes a duration; `max-deletion-share: 1` becomes `1.0`; an empty file yields no values; a string `$schema` is accepted and ignored while `$schema: 3` raises naming `$schema`; a missing file, invalid YAML and a top-level sequence each raise a usage error naming the path; `keeep: 3` raises naming `keeep` and the path; `keep: "three"` and `fail-on-skip: "yes"` raise naming the key; `execute: true` and `execute: false` raise the execute-flag message; `password: s3cret` and `url: https://bot:s3cret@nexus.example.com` raise naming the key and `NEXUS_PASSWORD`, with `s3cret` absent from the message; a file holding both `execute` and an unknown key reports `execute`
- [x] 1.2 Implement `config load` in `config.nu` — `open --raw | from yaml` regardless of extension, one key table carrying each key's internal name, type, schema constraints and description, a separate refused-keys table with its reasons checked first, `$schema` accepted as an ignored string — and verify the tests in 1.1 pass and `nu -c 'use nexus-cleanup'` still prints nothing
- [x] 1.3 Check Nushell 0.115.1's `from yaml` on `fail-on-skip: yes`, `keep: 010` and an unquoted `version-scheme: no`, and verify by test that each either parses to the intended type or is refused by the type check — never silently coerced into a different valid setting

## 2. Layering and validation

- [x] 2.1 Write failing tests in `tests/test-config.nu`: a flag overrides the file; `NEXUS_URL` overrides the file's `url` and a URL flag overrides both; the file overrides defaults for `format`, `keep` and `timeout`; `fail-on-skip` is on when either source sets it; command-line names replace a file `pattern`, a command-line pattern replaces file `repositories`, and the file's selection applies when the command line has none; no selection anywhere is the existing usage error; `keep: 0` and a `from-path` lacking its `version` group in the file raise errors naming `'keep' in <path>` and `'from-path' in <path>`, while the same values as flags still name `--keep` and `--from-path`; existing `config resolve` callers and tests are updated to the new signature where it changed
- [x] 2.2 Add `--file` to `config resolve` with per-setting layering, selection resolved as one unit, source-aware setting names in every validation message, a stderr diagnostic when the file's `url` is overridden, and `config_file` in the resolved record; verify the tests in 2.1 and the whole existing `test-config.nu` pass

## 3. Entrypoint

- [x] 3.1 Write failing tests in `tests/test-cli.nu`: `--config` naming an invalid file exits 2 with the file named, before any request; `--config` plus `--keep 5` uses 5; a file-configured run without `--execute` reports mode `dry-run`; `--help` still states each flag's default; `--version` with a broken `--config` still prints only the version and exits 0
- [x] 3.2 Remove the defaults from `def main`, state each default in the flag's comment, add `--config`, call `config load` then `config resolve --file`, and verify the tests in 3.1 and the existing CLI tests pass
- [x] 3.3 Add `--require-cap` (a flag only, absent from the key table) to `config resolve` and the entrypoint, and verify by tests in `test-config.nu` and `test-cli.nu` that with it a run with no cap from any source exits 2 naming `--max-deletions` and `--max-deletion-share` before any request, dry or executing; that a cap from the file or a flag satisfies it; that it never sets `execute`; and that `require-cap: true` in a file is refused as an unknown key

## 4. JSON Schema

- [x] 4.1 Write failing tests in `tests/test-config-schema.nu`: the generated schema declares draft 2020-12 and `additionalProperties: false`; its properties are exactly the recognised keys plus `$schema`, `execute` and `password`; `execute` and `password` are never-valid `{"not": {}}` schemas whose descriptions name `--execute` and `NEXUS_PASSWORD`; each recognised key's type, `minimum`, range, enum and pattern match the key table, with the enums equal to `FORMATS` and `SCHEMES`; every URL, duration and `from-path` value the tool accepts (loaded and resolved) in `tests/fixtures/config/` matches the corresponding schema pattern (checked with Nushell's regex engine on the ECMA-compatible subset the patterns use); and the committed `schema/config.schema.json` equals the generator's output byte for byte
- [x] 4.2 Implement `tools/generate-config-schema.nu` (sorted keys, fixed indentation, trailing newline), generate and commit `schema/config.schema.json`, and verify the tests in 4.1 pass, two consecutive runs produce identical files, and `.dockerignore` still excludes `schema/` and `tools/`

## 5. Report

- [x] 5.1 Append `config_file` after `tool_version` in `report summary`, pass it from `run.nu`, and verify by test in `tests/test-report.nu` that it holds the path verbatim, is empty without a file, is the last aggregate key with `tool_version` directly before it, and that CSV columns are unchanged

## 6. Documentation, examples and CI

- [x] 6.1 Add example configuration files under `examples/configs/` — a yum proxy selection and the raw `--from-path` / `date` case — each starting with the tag-pinned `yaml-language-server` modeline, and verify by test that each passes `config load`
- [x] 6.2 Document in `README.md` the `--config` option, the key table (checked against the key table in `config.nu` by a test), the layering rules, the refused keys and why, the quoting advice for patterns, the schema and its modeline with the advice to pin the tag matching the image, and include the raw example from `examples/configs/` as the worked file
- [x] 6.3 Write `examples/ci/run-configs.sh`, a POSIX `sh` loop over `$CONFIG_DIR/*.yaml` (default `configs`) in sorted order that always passes `--require-cap` and passes only an optional `--execute` through, carries on past a failing file, writes `reports/<basename>.<mode>.json` and `reports/<basename>.<mode>.summary.json` (mode `dry-run` or `execute`), fails on an empty directory, and ends with the aggregate exit code (first code other than 0 and 4, else 4, else 0); verify it with a test that runs it under BusyBox `sh` in `ghcr.io/nushell/nushell:0.115.1-alpine` against a stub `nexus-cleanup` returning chosen exit codes for three files (0/4/0 → 4, 0/3/4 → 3, empty directory → failure, `--execute` reaching the stub only when given)
- [x] 6.4 Rework the GitLab, Forgejo and both Jenkins examples into one dry-run job and one manual execute job that call `sh examples/ci/run-configs.sh` with `CONFIG_DIR=examples/configs` (the script always passes `--require-cap`), with the checkout enabled and the shared `resource_group`; verify each YAML pipeline file parses and that only the execute job passes `--execute`
- [x] 6.5 Add a `config-schema` job to `.github/workflows/tests.yml` (the `test` job's Nushell container has no Node) that runs `ajv-cli` in strict mode through `npx`, at exact versions pinned in `env:` as in `commits.yml`, with `--spec=draft2020` against `schema/config.schema.json` over every file in `examples/configs/`; verify it passes on the branch and fails on a deliberately broken copy (for example `keeep: 3`) in a throwaway commit or local run
- [x] 6.6 Record in `AGENTS.md` the standing decisions: `execute` and `password` are never file settings, the file is always parsed as YAML, defaults live only in `config resolve`, the selection is replaced as a unit, and the schema is generated from the key table, never hand-edited, looser rather than stricter where inexact, versioned by release tag and kept out of SchemaStore and the image; add `schema/` and `examples/configs/` to the layout; verify the text matches the implemented behaviour

## 7. Integration

- [x] 7.1 Extend `tests/test-end-to-end.nu` with a run driven by a configuration file against the recorded fixtures and verify its decisions equal those of the same settings passed as flags
- [x] 7.2 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and confirm the whole suite passes
- [x] 7.3 Run a dry run with a configuration file against the reference instance and confirm the report's `config_file` and decisions match the equivalent flag-driven dry run; open an example file in an editor with the YAML language server and confirm a misspelt key and `execute` are flagged with their descriptions

## Workflow follow-up

- Archive the change once merged.
- Apply `add-hosted-raw-cleanup` after this change; it adds the `allow-hosted` key to the table introduced here, and the schema with it.
