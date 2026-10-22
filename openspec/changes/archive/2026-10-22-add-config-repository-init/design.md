## Context

See `proposal.md` for motivation and `specs/` for the contract. Relevant current state, assuming
`add-config-file` has landed:

- The entrypoint is a single `def main` with a positional `...repositories` and run flags;
  `--version` short-circuits before configuration is read.
- The image copies `nexus-cleanup.nu`, the `nexus-cleanup/` module directory and the launcher;
  `.dockerignore` allow-lists exactly those. Anything placed inside `nexus-cleanup/` reaches the
  image with no `Containerfile` change.
- `nexus-cleanup/version.nu` holds `VERSION`, rewritten by release-please through a `generic`
  extra-file marker.
- The example pipelines (after `add-config-file`) loop over a configuration directory, and
  `examples/configs/` holds sample configuration files validated by `ajv-cli` in CI.
- The examples currently pin the image by hand (`0.1.0`) and nothing moves those pins at release.

## Goals / Non-Goals

**Goals:**

- A repository written by `init` works unedited apart from `configs/example.yaml`, with every pin
  agreeing.
- One source for pipelines: the templates. The examples are rendered from them.
- The loop that every pipeline relies on is tested once, hermetically.

**Non-Goals:**

- A template language. Templates are whole files with a handful of placeholders.
- Merging into existing files (`.vscode/settings.json` a user already has, for example).

## Decisions

### `init` is a Nushell subcommand of the entrypoint

`def "main init"` sits beside `def main`. Nushell dispatches the subcommand when the first
argument is `init`, so the run's positional repositories and flags never see it, and the launcher's
`def --wrapped` passes it through unchanged. The rendering and writing live in a new module file,
`scaffold.nu`, exported from `mod.nu`; the entrypoint stays a thin shell.

A repository literally named `init` can no longer be passed positionally. It stays reachable by
`--pattern init` or a configuration file's `repositories`, which the cli delta records.

*Alternative considered:* a `--init` flag on `main`. Rejected: `init` takes its own options
(`--ci`, `--editor`, `--force`), which would then mix with every run flag in one signature and
one `--help`.

### Planning is separate from writing

`scaffold plan --ci <system> --editor <list> --version <v>` returns a list of
`{path, content}` records and touches nothing — the whole output can be asserted in tests without
a filesystem. `scaffold write <plan> <dir> --force` checks every path first, fails listing all
conflicts unless `--force`, then saves each file. A failure part-way through a write (disk full,
permission denied) stops and names the paths already written; conflicts, invalid choices and
filesystem failures all exit with the usage error code, because each is the operator's
environment or arguments being wrong, not Nexus.

### Templates are files in the module, with placeholders only

Templates live under `nexus-cleanup/templates/` — `ci/<system>/…`, `common/…`, `editors/<editor>/…`
— and are located relative to `scaffold.nu` with `path self`, which works at the 0.115.1 floor and
from any working directory. Rendering replaces `{{version}}`, `{{image}}` and `{{schema_url}}`
and nothing else; there are no conditionals or loops, so each template reads as the file it
becomes. A test fails if any rendered file still contains `{{`.

- `{{image}}` = `ghcr.io/bond-os/nexus-cleanup:{{version}}`
- `{{schema_url}}` = `https://raw.githubusercontent.com/bond-os/nexus-cleanup/v{{version}}/schema/config.schema.json`

`{{version}}` is `VERSION`. Run from a source checkout between releases, that is the last
release, so the pins point at an image and schema that exist; the image is the supported way to
run `init`.

*Alternative considered:* templates as string constants in Nushell source. Rejected: a pipeline
inside a Nushell string loses its own syntax highlighting and quoting, which is where mistakes
hide.

### The loop is one POSIX `sh` script that every pipeline calls

`init` writes `ci/run-configs.sh`, and each pipeline template calls `sh ci/run-configs.sh` for the
dry run and `sh ci/run-configs.sh --execute` for the execute job. The script implements the loop
`add-config-file` specified — sorted files, carry on past failures, a report and summary per file
under `reports/`, failure on an empty directory, the aggregate exit code — once instead of four
times in four CI dialects. It runs under BusyBox `sh` inside the image for GitLab, Forgejo and
`jenkins-docker`; `jenkins-sh` runs it in the image with `docker run --entrypoint sh`. Invoking it
through `sh` means no executable bit is needed, which `save` cannot set.

`--execute` is the script's only argument and is passed straight through, so the tool's own
dry-run default still decides. The script always adds `--require-cap`, so a configuration file
without a deletion cap fails in the dry run.

*Alternative considered:* the loop inline in each pipeline, as `add-config-file` first wrote it.
Rejected: four copies to keep in step, and a loop embedded in CI YAML or Groovy cannot be run by
the hermetic suite.

### Each CI template keeps its system's current approach

GitLab and `jenkins-docker` use the image as the job container; `jenkins-sh` uses `docker run`;
Forgejo keeps the approach of the current example, with its pin rendered from `{{version}}`.
Scheduled or pushed pipelines run the dry-run job only; the execute job needs a person — a manual
job (GitLab), a `workflow_dispatch` input (Forgejo), an `input` step (Jenkins). This change moves
the existing, reviewed pipeline shapes into templates rather than redesigning them.

### The example configuration fails loudly until edited

`configs/example.yaml` selects `repositories: [replace-me]` and shows the other settings
commented out. A repository of that name does not exist, so the first pipeline run fails with
"repository 'replace-me' does not exist" — exit 3 — before anything is enumerated. A placeholder
pattern would match nothing and exit 0, which is a green pipeline doing nothing.

### Editor files

- **VS Code**: `.vscode/settings.json` maps `{{schema_url}}` to `configs/*.yaml` and
  `configs/*.yml` under `yaml.schemas`; `.vscode/extensions.json` recommends `redhat.vscode-yaml`.
- **IntelliJ-based IDEs**: `.idea/jsonSchemas.xml`, the project-level JSON Schema mapping file the
  IDE writes when a mapping is added under *Languages & Frameworks | Schemas and DTDs | JSON Schema
  Mappings*, mapping the same URL to the same patterns. Its exact shape is taken from a file the
  IDE itself wrote, not from memory, and checked by opening the generated repository in an IDE
  before release.

The modeline in each configuration file stays even with editor files written: it covers editors
without a project mapping and anyone opening a single file.

### Examples are rendered from the templates, with release markers

`tools/render-examples.nu` writes `examples/<system>/` for each system as `init --ci <system>
--editor vscode --editor intellij` would, replacing today's `examples/gitlab-ci/`, `forgejo/`
and `jenkins/`. `examples/configs/` stays as the gallery of configuration files.

So that a release moves the examples' pins together with `version.nu`, the renderer — and only the
renderer — adds release-please's `x-release-please-version` marker to every line holding a pin,
and `release-please-config.json` lists those files as `generic` extra-files. `init` itself never
writes markers. The drift test renders with markers at `VERSION` and compares byte for byte, so it
passes on the release PR, where release-please has updated both. Where an inline marker would
break a line's meaning — the modeline must stay parseable, JSON has no comments outside VS Code's
JSONC — the marker goes on its own comment line using `x-release-please-start-version` /
`x-release-please-end`, or the file is rendered without a pin and listed in the test as such.

## Risks / Trade-offs

- [The IntelliJ file format is wrong or version-dependent] → It is captured from a real IDE, the
  repository opened in a current IntelliJ IDEA and one other JetBrains IDE before release, and the
  README states which versions were checked.
- [`.idea/` is ignored by a global gitignore and the mapping never reaches teammates] → `init`
  lists `.idea/jsonSchemas.xml` among written files, and the README says to `git add -f` it.
- [`--force` overwrites a user's own `.vscode/settings.json`] → Conflicts are listed before
  `--force` is needed, and the README says to merge `yaml.schemas` by hand instead.
- [A release marker breaks a file it is placed in] → The drift test also checks that every
  rendered example parses (YAML, JSON with comments, XML) and the modeline is recognised.
- [Generated repositories drift from newer tool versions] → Out of scope by design; pins move
  deliberately, as the release design intends.

## Migration Plan

`examples/` paths change; links in `README.md` are updated in the same change. No runtime
behaviour changes for cleanup runs.
