## 1. Templates and rendering

- [ ] 1.1 Move the reviewed pipelines from `examples/` (as left by `add-config-file`) into `nexus-cleanup/templates/ci/{gitlab,forgejo,jenkins-docker,jenkins-sh}/`, the loop script into `templates/common/ci/run-configs.sh`, and add `templates/common/` files for `configs/example.yaml` (modeline, `repositories: [replace-me]`, other settings commented), `.editorconfig` and `.gitattributes`; replace every pin with `{{image}}`, `{{schema_url}}` or `{{version}}`, set the loop's default directory to `configs` and the pipelines' calls to `sh ci/run-configs.sh`; verify by `grep` that no literal version or `ghcr.io/…:` tag remains in any template
- [ ] 1.2 Write failing tests in `tests/test-scaffold.nu` for `scaffold plan`: for each CI system the planned paths are the pipeline at its system path, `ci/run-configs.sh`, `configs/example.yaml`, `.editorconfig` and `.gitattributes`, and nothing else; `--editor vscode` adds `.vscode/settings.json` and `.vscode/extensions.json`, `--editor intellij` adds `.idea/jsonSchemas.xml`, both may be given; with version `0.3.0` every rendered file referencing the image uses `ghcr.io/bond-os/nexus-cleanup:0.3.0` and every schema reference uses the `v0.3.0` URL; no rendered file contains `{{`; `.editorconfig` and `.gitattributes` match the spec byte for byte; an unknown CI system or editor raises a usage error listing the choices; `plan` touches no file
- [ ] 1.3 Implement `nexus-cleanup/scaffold.nu` with `scaffold plan` (templates located with `path self`, placeholder substitution only, an internal option adding release markers used only by the renderer), export it from `mod.nu`, and verify the tests in 1.2 pass and `nu -c 'use nexus-cleanup'` still prints nothing
- [ ] 1.4 Verify by test that the rendered `configs/example.yaml` passes `config load`, and that loading it into a cleanup run against a stubbed listing fails with the error naming `replace-me` before any component request

## 2. Writing and the subcommand

- [ ] 2.1 Write failing tests for `scaffold write` in `tests/test-scaffold.nu` using a temporary directory: an empty or missing target receives every planned file and the directory is created; existing `.gitlab-ci.yml` and `.editorconfig` make it fail listing both with nothing written; `--force` overwrites those two, writes the rest, and leaves an unrelated `configs/prod.yaml` unchanged; written paths are listed on stderr and stdout is empty
- [ ] 2.2 Implement `scaffold write` (check all paths, then write; stop and name written paths on a filesystem error) and verify the tests in 2.1 pass
- [ ] 2.3 Write failing tests in `tests/test-cli.nu`: `init --ci gitlab <tmp>` exits 0 with no `NEXUS_URL`, no selection and no request; `init` without `--ci`, with `--ci github` or `--editor emacs` exits 2 listing the choices and writes nothing; `init --ci gitlab --execute` exits 2; a cleanup run with `--pattern init` still selects a repository named `init`
- [ ] 2.4 Add `def "main init"` with `--ci`, repeatable `--editor`, `--force` and an optional directory to the entrypoint, calling `scaffold plan` with `VERSION` and `scaffold write`, and verify the tests in 2.3 and the existing CLI tests pass

## 3. Generated pipeline behaviour

- [ ] 3.1 Extend the loop-script test from `add-config-file` to run the rendered `ci/run-configs.sh` from an `init` output tree, and verify the 0/4/0 → 4, 0/3/4 → 3 and empty-directory cases and that `--execute` reaches the tool only when given
- [ ] 3.2 Verify by test that in each rendered pipeline `--execute` appears only in the execute job, that the execute job is manual (`when: manual` for GitLab, a `workflow_dispatch` input for Forgejo, an `input` step for both Jenkins variants) and that scheduled triggers reach only the dry-run job; verify each rendered YAML pipeline parses

## 4. Editor support

- [ ] 4.1 Create a JSON Schema mapping for `configs/*.yaml` and `configs/*.yml` to a remote URL in a current IntelliJ IDEA, copy the `.idea/jsonSchemas.xml` it writes into `templates/editors/intellij/` with the URL replaced by `{{schema_url}}`, and verify by test that the rendered file parses as XML and names the pinned URL and both patterns
- [ ] 4.2 Add `templates/editors/vscode/settings.json` (`yaml.schemas` mapping `{{schema_url}}` to both patterns) and `extensions.json` (recommending `redhat.vscode-yaml`), and verify by test that both parse as JSON with comments and carry the pinned URL
- [ ] 4.3 Initialise a repository with `--editor vscode --editor intellij`, open it in VS Code with the recommended extension and in IntelliJ IDEA plus one other JetBrains IDE, create a new file in `configs/` without a modeline, and confirm completion and that `keeep` and `execute` are flagged with their descriptions; record the IDE versions checked in `README.md`

## 5. Examples and release

- [ ] 5.1 Write `tools/render-examples.nu` that renders `examples/<system>/` for every CI system with both editors and release markers on every pinned line (block markers where an inline comment would break the line), remove the old `examples/gitlab-ci/`, `examples/forgejo/` and `examples/jenkins/`, render, and verify that every rendered file parses (YAML, JSON with comments, XML) and the modeline in `configs/example.yaml` is still recognised by the YAML language server
- [ ] 5.2 Add an example-drift test that renders all systems at `VERSION` with markers into a temporary directory and compares them byte for byte with `examples/<system>/`; verify it passes, then fails after editing one example by hand
- [ ] 5.3 List every rendered example file holding a pin in `release-please-config.json` as a `generic` extra-file, and verify with release-please's dry run (`npx release-please release-pr --dry-run` at a pinned version, or by applying its generic updater in a test) that a version bump moves every pin in `examples/` and leaves the drift test passing
- [ ] 5.4 Extend the `ajv-cli` CI step to validate `examples/*/configs/*.yaml` as well as `examples/configs/`, and verify it passes

## 6. Image and documentation

- [ ] 6.1 Extend `.github/scripts/image-smoke.sh` with an `init --ci gitlab` run into a mounted empty directory under an arbitrary UID with group 0, a read-only root filesystem and no capabilities, and with the documented rootless mappings; verify the files appear, are owned as documented, and pin the image's own version; verify the image holds `templates/` and no `tools/` file
- [ ] 6.2 Document in `README.md` a "Getting started" section with the `docker run … init` invocation including the user mapping, the four CI choices, the editor options, `--force` and its limits, committing `.idea/jsonSchemas.xml` with `git add -f`, merging an existing `.vscode/settings.json` by hand, and the example repository trees under `examples/<system>/`; update every link to the old example paths
- [ ] 6.3 Record in `AGENTS.md` the standing decisions: templates are the single source of the examples, `init` never writes release markers while the renderer always does, the loop lives in one shared `sh` script, the example configuration selects a repository that cannot exist, and `init` writes no `AGENTS.md` or `README.md`; update the layout; verify the text matches the implementation

## 7. Integration

- [ ] 7.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and confirm the whole suite passes
- [ ] 7.2 Initialise a GitLab repository from a locally built image, push it to a scratch GitLab project with the reference instance's credentials as CI variables, edit `configs/example.yaml` to one reference proxy, and confirm the scheduled-style dry-run job produces a report per file while the execute job waits for a person

## Workflow follow-up

- Apply after `add-config-file` (and after `add-hosted-raw-cleanup` if both are in flight, so the rendered `examples/configs/` gallery includes the hosted example); archive after `add-config-file` is archived.
