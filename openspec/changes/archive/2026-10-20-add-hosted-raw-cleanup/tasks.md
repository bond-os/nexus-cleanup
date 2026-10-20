## 1. Fixture

- [x] 1.1 Record one raw hosted repository from the reference instance with `nu tools/record-fixtures.nu --max-pages 1 packer-bases` (or `raw-iso` if smaller), and verify that `tests/test-fixture-redaction.nu` and `tests/test-fixtures-clean.nu` pass, that the re-recorded `repositories.json` differs only where Nexus changed, and that the hosted components have the same field shape as `raw-proxy-repo.almalinux.org-page-0.json`

## 2. Eligibility

- [x] 2.1 Write failing tests in `tests/test-api.nu` for `api select-repositories` over a listing with a proxy, a raw hosted, a docker hosted and a group repository: a named proxy is accepted with and without `--allow-hosted`; the named raw hosted repository is accepted only with `--allow-hosted`, and without it the error names the repository, `hosted` and `--allow-hosted`; the named docker hosted repository is refused with `--allow-hosted` by an error naming its format and "only raw"; the group repository is refused either way; a pattern matching every repository selects only the proxy with and without `--allow-hosted`; an unknown name is still refused
- [x] 2.2 Rename `api select-proxies` to `api select-repositories` in `api.nu` with the eligibility rules above, move the existing `select-proxies` tests to the new name, and verify the tests in 2.1 and the moved tests pass and that no reference to `select-proxies` remains in the repository
- [x] 2.3 Make `api repository-config` build its URL from the repository's `type`, and verify by a stubbed test that an apt hosted repository's configuration is requested from `/repositories/apt/hosted/<name>` and an apt proxy's from `/repositories/apt/proxy/<name>`

## 3. Configuration and entrypoint

- [x] 3.1 Add `allow_hosted` to `config resolve` (default false, `flag or file`) and the `allow-hosted` boolean key, with its description, to the configuration key table, regenerate `schema/config.schema.json` with `tools/generate-config-schema.nu`, and verify by tests in `test-config.nu`, `test-config-file.nu` and `test-config-schema.nu` that it defaults to false, is set by either source, is refused as a non-boolean, never sets `execute`, and appears in the committed schema as a boolean
- [x] 3.2 Add `--allow-hosted` to the entrypoint and pass it through, and verify by a test in `test-cli.nu` that `--allow-hosted` without `--execute` reports mode `dry-run` and that `--help` describes the switch

## 4. Run

- [x] 4.1 Write failing tests in `tests/test-run.nu` with a stubbed listing declaring the synthetic `path-derived-layout` repository as raw hosted: with `--allow-hosted`, `--from-path`, `--version-scheme date --keep 14 --execute`, exactly the components of the oldest directories are deleted and no outside-pattern file receives a deletion request; without `--from-path`, nothing is deleted, every component is kept, and stderr names the repository and `--from-path`; with `--from-path`, that diagnostic is absent; a pattern matching the hosted repository excludes it with a note to name it; a stubbed deletion failure on one file of a directory leaves the other deletions done, records the error on that file, and exits 1
- [x] 4.2 Switch `run.nu` to `api select-repositories`, pass the opt-in, add the type to the enumeration note, emit the no-pattern diagnostic and the hosted-excluded note, and verify the tests in 4.1 and the whole existing `test-run.nu` pass

## 5. Documentation

- [x] 5.1 Update `README.md`: eligibility (proxies, plus named raw hosted repositories under `--allow-hosted`), the switch in the flag and file-key tables, a worked hosted example as a configuration file `examples/configs/raw-hosted-builds.yaml` (with the schema modeline, `allow-hosted`, `from-path`, `date`, `keep` and `max-deletions`), the dry-run-first advice, the partial-deletion behaviour, and the backfill caveat; verify the worked file passes `config load` and the CI `ajv-cli` step validates it against the schema
- [x] 5.2 Update `AGENTS.md`: the project description, the "refusal of non-proxy repositories" safety layer, and a standing decision recording why hosted support is raw-only, name-only and opt-in, and why no cap is mandatory; update the purpose lines of `openspec/specs/nexus-cleanup/nexus-api-client/spec.md` and `openspec/specs/nexus-cleanup/retention-policy/spec.md`, which say "proxy" and "cached"; verify the text matches the implemented behaviour

## 6. Integration

- [x] 6.1 Extend `tests/test-end-to-end.nu` with the recorded raw hosted fixture under `--allow-hosted` and verify that its dry and executing passes agree on every decision and that every existing assertion is unchanged
- [x] 6.2 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and confirm the whole suite passes
- [x] 6.3 On the reference instance, create an expendable raw hosted repository holding a small dated layout plus a version directory, run a dry run and then an executing run from a configuration file with `allow-hosted: true`, and confirm the version directory reports `outside-pattern`, exactly the directories beyond the keep count are deleted, and a dry run of `packer-bases` without `--from-path` deletes nothing and prints the diagnostic

## Workflow follow-up

- Apply after `add-config-file`; archive only after `add-config-file` is archived, since this change's `config-file` delta modifies the spec that change creates.
