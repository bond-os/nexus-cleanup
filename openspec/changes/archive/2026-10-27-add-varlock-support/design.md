## Context

See proposal.md for why. What exists today:

- `scaffold init-args` parses `init`'s arguments itself (`--ci`, repeatable `--editor`, `--force`,
  a directory); `scaffold plan` selects template areas — `common/`, `ci/<system>/`,
  `editors/<editor>/` — and `scaffold write` refuses existing paths unless `--force`.
- Templates are whole files at the path they are written to; rendering replaces `{{version}}`,
  `{{image}}` and `{{schema_url}}` only. `tools/render-examples.nu` renders `examples/<system>/`
  as `init --ci <system> --editor vscode --editor intellij`, and `tests/test-examples.nu` compares
  byte for byte.
- `init` writes no `.gitignore` today.
- In this repository, `.nexus.env.example` documents `NEXUS_URL`, `NEXUS_USERNAME` and
  `NEXUS_PASSWORD` for `tools/record-fixtures.nu`, which reads only `$env`; `.gitignore` ignores
  `.nexus.env`.
- The hermetic suite runs inside the Nushell image: no git, no varlock.

## Goals / Non-Goals

**Goals:**

- The operator's `.env.schema` makes a forgotten URL or password fail in varlock, before the
  tool runs.
- Nothing about varlock reaches the tool, the image or a generated pipeline.

**Non-Goals:**

- Generating per-environment files, or a variable that selects the environment: the README shows
  the pattern, the operator adds it when they have more than one Nexus.

## Decisions

### `--env <tool>`, parsed and planned like `--editor`

A new area `env/<tool>/` in the templates, selected by `--env varlock`; repeated identical
values collapse as `--editor`'s do. A value-taking option keeps the choice list in one record
(as `CI_SYSTEMS` and `EDITORS`) and leaves room for another tool without another flag.

Alternative: a boolean `--varlock`. Shorter, but a second tool would add a second flag and the
help text would stop listing choices in one place.

### The templates hold no placeholders

`.env.schema` carries no version, image or schema address — its only link to a release would
be a docs URL, and it has none — so it needs no rendering and no release marker, and an upgrade
never touches it. The root decorators set `@defaultSensitive=false` and `@defaultRequired=false`,
and each item states its own `@required` / `@sensitive`, so the file reads correctly item by item
without knowing varlock's defaults: `@defaultSensitive` defaults to `true`, and
`@defaultRequired` to `infer` — required exactly when the schema gives the item a value, which
would make every value-less item here optional.

### `init` writes a `.gitignore`, and it holds only varlock's value files

Without it, the first `git add .` after `varlock(prompt)` or a hand-edited `.env.local` commits a
password. It lists `.env`, `.env.local` and `.env.*.local`, nothing else: `reports/` and editor
directories are the operator's choice, and a broader file would collide with more existing ones.
An existing `.gitignore` is refused like any other existing file, and `--force` overwrites it
without merging — the README tells operators with a `.gitignore` to leave out `--env` and add the
three lines themselves, as it already does for `.vscode/settings.json`.

The template `nexus-cleanup/templates/env/varlock/.gitignore` and its rendered copies in
`examples/<system>/` are live `.gitignore` files in this repository. That is deliberate: they
only ignore varlock value files in their own directories, which also keeps a value file made
during the manual check out of a commit here. Storing the template as `gitignore` and renaming it
on write was rejected: it would break "a template is stored at the path it is written to" and
give the renderer and `init` their first special case. AGENTS.md records this beside the other
`init` decisions, so it is not "fixed" later.

### Local runs mount only `configs/`, read-only

`varlock run -- docker run --rm -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD
-v "$PWD/configs:/work/configs:ro" ghcr.io/bond-os/nexus-cleanup:X.Y.Z --config configs/x.yaml`.
`-e NAME` without a value forwards what varlock injected into the `docker` process, so no secret
appears on the command line. The image's working directory is `/work`, so the relative
`--config` path resolves with no `-w`. Nothing is written into the mount — the report goes to
standard output — so the container's user needs read access only, and no `--user` mapping or
rootless variant is needed. The line carries one image pin and an `x-release-please-version`
marker.

The README places the section next to "Configuration files" — it is for trying an edited file —
and adds:

- **A Nexus on the operator's own machine** is `host.docker.internal` from inside the container,
  not `localhost`, which is the container itself; on Linux this needs
  `--add-host=host.docker.internal:host-gateway`. Because the process environment beats every
  varlock file, a one-off `NEXUS_URL=http://host.docker.internal:8081 varlock run -- docker run …`
  overrides the schema's value for that run only.
- **A file that sets `summary-out`** cannot write into the read-only mount and needs the writable
  mount from "In a container". It cannot be switched off from the command line: an empty
  `--summary-out ""` counts as not given, so the file's value wins. Few files set it, since the CI
  loop passes `--summary-out` itself.

"In a container" already shows a local run with a writable workspace mount; the two commands
differ on purpose and the new section links back to it rather than repeating it.

Alternative: running `ci/run-configs.sh` locally. Rejected in exploration: the loop writes
summaries into the mount, which needs a `--user` mapping that an unevaluated `$NEXUS_CLEANUP`
cannot express.

### Per-environment files: shown with their precedence

The README's per-environment paragraph (`@currentEnv` with tracked `.env.staging` and
`.env.production`) states varlock's order in one line — `.env.schema` < `.env` < `.env.local` <
`.env.<env>` < `.env.<env>.local` < the process environment — and its two consequences for this
tool: a `NEXUS_PASSWORD` still exported in the shell silently beats `.env.local` and `keychain()`,
and a tracked `.env.production` beats `.env.local`, so a per-machine override for one
environment goes in `.env.production.local`.

### This repository's `.env.schema` replaces `.nexus.env.example`

Same three variables; `NEXUS_URL` defaults to the reference instance (`http://localhost:8081`),
`NEXUS_USERNAME` to `admin`, `NEXUS_PASSWORD` is sensitive with no value. `.gitignore` gains the
three value-file patterns and keeps `.nexus.env`, so an existing local copy is still never
committed. `.dockerignore` is an allow-list and needs no change. AGENTS.md: the Runtime section
says varlock is an optional external wrapper, outside the Nushell-only rule like Docker; the
re-recording instructions show `varlock run --` and still accept exported variables.

### Tests check content; git and varlock behaviour is checked once by hand

The suite asserts that the files are written only with `--env varlock`, that `.env.schema`
declares exactly the three variables with the required decorators and contains no URL or version,
that `.gitignore` holds exactly its three lines, and the usage error for an unknown tool. The
scenarios that need `git` or `varlock` are verified manually against the rendered example and
the varlock version used is recorded in the README.

## Risks / Trade-offs

- [varlock changes its decorator syntax] → The files are small and the checked version is
  recorded; an operator on another version reads one short file. Renovate does not track it,
  since nothing in this repository executes it.
- [Read-only bind mounts on SELinux hosts are denied without a relabel] → The README adds
  `:ro,z` as the variant for such hosts.
- [varlock's `url` type refuses `http://`] → Not yet confirmed either way; the reference instance
  is `http://localhost:8081` and many internal Nexus instances are plain http. Checked in
  tasks.md; if it refuses, `@type=url` is dropped from both schema files and the reason recorded,
  since the tool's own URL check runs anyway.
- [`--force` replaces an operator's `.gitignore`] → Only when they asked for both `--env varlock`
  and `--force`; the `init` message lists every file it writes, and the README warns.
