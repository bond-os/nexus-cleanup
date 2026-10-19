## Why

With configuration files and a published schema, the intended setup is a small private
repository: one pipeline that loops over `configs/*.yaml`, the configuration files themselves,
and editor settings that give schema completion. Assembling that by hand means copying a
pipeline from `examples/`, finding every place a version must be pinned — the image tag, the
schema URL in each file and in each editor's settings — and keeping them in agreement. A missed
pin is exactly the silent drift the release design exists to prevent.

The tool already knows its own version, so it can write that repository with every pin
consistent.

## What Changes

- **`nexus-cleanup init`**, a subcommand that writes a configuration repository into a directory
  (the working directory by default, which is the mounted workspace when run from the image).
  It needs no Nexus, no environment and no credentials, and makes no request.
- **`--ci <system>`, required**: one of `gitlab`, `forgejo`, `jenkins-docker`, `jenkins-sh`.
  The pipeline written has a dry-run job and a manual execute job, each looping over
  `configs/*.yaml` exactly as the `add-config-file` examples do.
- **Always written**: the pipeline, `ci/run-configs.sh` (the loop every pipeline calls, as in the
  `add-config-file` examples), `configs/example.yaml` (with the schema modeline), an
  `.editorconfig` (`root = true`; UTF-8 and LF for every file) and a `.gitattributes`
  (`* text=auto eol=lf`), so a Windows checkout cannot put CR into the pipeline's shell.
- **`--editor vscode` / `--editor intellij`, repeatable, none by default**: VS Code gets
  `.vscode/settings.json` mapping the schema to `configs/*.yaml` and `.vscode/extensions.json`
  recommending Red Hat's YAML extension; IntelliJ-based IDEs get `.idea/jsonSchemas.xml` with
  the same mapping.
- **Everything is pinned to the running tool's version**: the image tag `X.Y.Z` in the pipeline,
  and the schema URL at tag `vX.Y.Z` in the example file and every editor mapping.
- **Existing files are never overwritten silently.** If any file `init` would write already
  exists, it lists them all and writes nothing; `--force` overwrites those files and touches
  nothing else.
- **`examples/<ci>/` becomes `init` output**, rendered by a development tool and checked by a test,
  so the browsable examples and what `init` writes cannot diverge. The templates ship inside the
  module and therefore in the image.

Non-goals: an `AGENTS.md` or `README.md` in the generated repository; editor support beyond VS
Code and IntelliJ-based IDEs (the modeline in each file serves every editor using the YAML
language server); updating an existing repository to a newer version (re-run with `--force`, or
bump the pins by hand); creating the remote repository or CI variables.

## Capabilities

### New Capabilities
- `nexus-cleanup/config-repository`: initialising a configuration repository — which files are
  written for which choices, how they are pinned to the tool's version, what the generated
  pipeline guarantees, and how existing files are protected.

### Modified Capabilities
- `nexus-cleanup/cli`: the tool gains a subcommand that, like the version flag, reads no run
  configuration.
- `nexus-cleanup/distribution`: the image carries the templates `init` writes, and `init` run
  from the image writes into the mounted workspace.

## Impact

- **Code**: a new `nexus-cleanup/scaffold.nu` (rendering and writing), templates under
  `nexus-cleanup/templates/`, `def "main init"` in the entrypoint, `mod.nu` export.
- **Tools**: `tools/render-examples.nu` regenerates `examples/<ci>/`.
- **Release**: `release-please-config.json` lists the rendered example files as `generic`
  extra-files, so the release PR moves their pins together with `version.nu`.
- **Tests**: a new `tests/test-scaffold.nu`; an example-drift test; the image smoke check gains
  an `init` run into a mounted workspace.
- **Examples**: `examples/gitlab-ci/`, `examples/forgejo/` and `examples/jenkins/` are replaced by
  rendered trees `examples/<ci>/`; `examples/configs/` stays as the gallery of configuration
  files.
- **Docs**: `README.md` (getting started with `init`, the container invocation with
  `--user`), `AGENTS.md` (templates are the source of the examples; markers explained).
- **Depends on**: `add-config-file` (the loop, the schema and its URL). Independent of
  `add-hosted-raw-cleanup`.
