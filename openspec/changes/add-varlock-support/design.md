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
without knowing varlock's defaults (which are the opposite: sensitive by default).

### `init` writes a `.gitignore`, and it holds only varlock's value files

Without it, the first `git add .` after `varlock(prompt)` or a hand-edited `.env.local` commits a
password. It lists `.env`, `.env.local` and `.env.*.local`, nothing else: `reports/` and editor
directories are the operator's choice, and a broader file would collide with more existing ones.
An existing `.gitignore` is refused like any other existing file, and `--force` overwrites it
without merging — the README tells operators with a `.gitignore` to leave out `--env` and add the
three lines themselves, as it already does for `.vscode/settings.json`.

### Local runs mount only `configs/`, read-only

`varlock run -- docker run --rm -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD
-v "$PWD/configs:/work/configs:ro" ghcr.io/bond-os/nexus-cleanup:X.Y.Z --config configs/x.yaml`.
`-e NAME` without a value forwards what varlock injected into the `docker` process, so no secret
appears on the command line. The image's working directory is `/work`, so the relative
`--config` path resolves with no `-w`. Nothing is written into the mount — the report goes to
standard output — so the container's user needs read access only, and no `--user` mapping or
rootless variant is needed. The line carries one image pin and an `x-release-please-version`
marker.

Alternative: running `ci/run-configs.sh` locally. Rejected in exploration: the loop writes
summaries into the mount, which needs a `--user` mapping that an unevaluated `$NEXUS_CLEANUP`
cannot express.

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
- [`--force` replaces an operator's `.gitignore`] → Only when they asked for both `--env varlock`
  and `--force`; the `init` message lists every file it writes, and the README warns.
