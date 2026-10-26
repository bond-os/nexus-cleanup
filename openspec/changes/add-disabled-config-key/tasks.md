# Tasks

## 1. The key

- [ ] 1.1 Let a `CONFIG_KEYS` row declare that it has no flag, and add `disabled` (field `disabled`, type `bool`, a description saying it skips the file on every run until removed and never enables anything); `config resolve` takes it from the file only and defaults it to `false`; verify with tests in `tests/test-config-file.nu` and `tests/test-config.nu`: `disabled: true` and `false` resolve, `disabled: "until later"` is a usage error naming `disabled` and the file, `enabled: false` is refused as an unknown key listing `disabled`
- [ ] 1.2 Regenerate `schema/config.schema.json` with `nu tools/generate-config-schema.nu` and make the README key table show `—` in the Flag column for a row without a flag; verify `tests/test-config-schema.nu` and the README table check in `tests/test-config-file.nu` pass, and that the schema accepts `disabled: true` and rejects `disabled: "yes"`

## 2. The disabled run

- [ ] 2.1 Append `disabled` after `config_file` in the aggregate built by `report summary`, `false` unless the run's configuration disabled it; verify `tests/test-report.nu` asserts the field order and the `false` default, and that CSV record columns are unchanged
- [ ] 2.2 Make `cleanup run` return first for a disabled configuration: write `nexus-cleanup: <file> is disabled; nothing was done` to standard error and return the report of no records with `disabled: true` and exit code 0, the mode as requested; verify with tests in `tests/test-run.nu` using a fetch stub that fails on any request — dry run, `--execute`, a command-line repository selection — each exiting 0 with the stderr line
- [ ] 2.3 Verify end to end in `tests/test-end-to-end.nu` (or `test-cli.nu`): a disabled file with JSON output prints a valid document with an empty record array, zero counts and `disabled: true`; with `format: csv` prints only the header row; with `--summary-out` writes the aggregate with `disabled: true`
- [ ] 2.4 Verify validation still applies: a disabled file with `keeep: 3`, with `execute: false`, and without a cap under `--require-cap` each exit 2 with the usual message; `disabled: false` behaves as no key
- [ ] 2.5 Add a case to `tests/test-run-configs.nu` with one disabled and one ordinary file: the loop runs both, keeps a `.json` report for each, and ends with the ordinary file's exit code; verify it passes

## 3. Template and documentation

- [ ] 3.1 Add the commented `# disabled: true` with its explanation to `nexus-cleanup/templates/common/configs/example.yaml`, re-render with `nu tools/render-examples.nu`; verify `tests/test-examples.nu` passes and the unedited example still loads as not disabled
- [ ] 3.2 README "Configuration files": a bullet on `disabled` — skipped on every run, still validated, exit 0, report and summary still written, no flag overrides it — and the report section's aggregate field list; verify the README's documented fields match `report summary`
- [ ] 3.3 AGENTS.md "A configuration file can never ask for deletion": record `disabled` as the deliberate exception to "no key switches the run mode" — it can only stop a run — and that a key that enables or widens anything stays forbidden; mention under "Configuration files: how they are read and layered" that a key table row may have no flag; verify by reading the diff against design.md

## 4. Integration

- [ ] 4.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and verify it passes; verify `nu -c 'use nexus-cleanup'` still prints nothing
- [ ] 4.2 Run `openspec validate add-disabled-config-key --strict` and verify it passes

## Workflow follow-up

- Commit as `feat:`; the aggregate gains a field, which the changelog line should mention.
- Archive the change after merge.
