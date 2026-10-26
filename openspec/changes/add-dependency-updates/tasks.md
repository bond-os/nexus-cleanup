# Tasks

## 1. Nushell base and checksum check

- [x] 1.1 Pin the `Containerfile` `FROM` and the `test` job container in `.github/workflows/tests.yml` as `ghcr.io/nushell/nushell:0.115.1-alpine@sha256:<index digest>`, taking the multi-arch index digest from `docker buildx imagetools inspect`; verify by building the image locally from the pinned `Containerfile` and running `nu tests/run-tests.nu` inside the image referenced by digest
- [x] 1.2 Add a `nushell-checksum` job to `.github/workflows/tests.yml` that reads `NU_VERSION` and `NU_SHA256` from `nexus-cleanup/templates/ci/forgejo/.forgejo/workflows/nexus-cleanup.yml`, downloads the asset the template installs and verifies it with `sha256sum -c`, printing version, pinned and actual checksum on mismatch; with values passed through `env:` only, and the existing actions pins reused; verify by running the job's script locally against the current template (passes) and against a copy with one checksum digit changed (fails, naming both checksums)

## 2. Renovate configuration

- [x] 2.1 Write `renovate.json`: `config:best-practices`, own `ignorePaths` (`tests/fixtures/**`, `openspec/**`), `enabledManagers` `github-actions`/`dockerfile`/`custom.regex`, weekly Monday-before-9am Europe/Warsaw schedule, `semanticCommits` enabled with scope `deps` and type `ci` by default, and a package rule disabling the native managers under `nexus-cleanup/templates/**` and `examples/**`; verify with `npx --yes --package renovate -- renovate-config-validator --strict renovate.json`
- [x] 2.2 Add the Nushell regex manager (`ghcr.io/nushell/nushell`, `docker` datasource) over README.md, AGENTS.md (image and floor), the Forgejo template and `examples/forgejo/`; group it with the native managers' `ghcr.io/nushell/nushell` references as one PR with type `fix`, no `minimumReleaseAge`, and `prBodyNotes` covering the seven-pin check and the checksum amend; verify with a local `renovate --platform=local --dry-run=extract` run that lists exactly seven `ghcr.io/nushell/nushell` occurrences at `0.115.1` / `0.115.1-alpine`, two of them with the pinned digest
- [x] 2.3 Add the npm regex managers over the workflow `env:` strings and the AGENTS.md hook line, grouping `@commitlint/cli` with `@commitlint/config-conventional` and leaving `ajv-cli` separate, three-day `minimumReleaseAge`; verify the extract run lists both commitlint packages twice each (workflow string, hook line) and ajv-cli once
- [x] 2.4 Verify the extract run reports every action from the three workflows, nothing from `nexus-cleanup/templates/`, `examples/` other than the Nushell pin, `tests/fixtures/` or `openspec/`, and no `ghcr.io/bond-os/nexus-cleanup` reference
- [x] 2.5 Verify with a local `--dry-run=lookup` run (GitHub token from `gh auth token` in the environment) that proposed branches carry the expected commit subjects, `fix(deps): …` for Nushell and `ci(deps): …` otherwise, that no update is marked for automerge, that no "pin digests" update is proposed, and that no digest would be written to README.md, AGENTS.md or the template

## 3. Documentation

- [x] 3.1 Update the comment on the `test` job's container image in `tests.yml` to say the pin is tag plus digest and moves through the Nushell update PR together with every other Nushell pin; verify by reading the diff
- [x] 3.2 Add a "Dependency updates" section to AGENTS.md (under Releases or beside Commits and merging) covering the hosted App and its trust trade-off, the three streams and their commit types, no automerge, the npm-only waiting period and why Nushell has none, the digest pin and why documentation stays tag-only, what the updater must never touch, and the checksum amend procedure; list `nushell-checksum` among the required checks and the Mend Renovate App under "Repository settings (configured by hand)"; update the Layout tree with `renovate.json`; verify that every decision in design.md either has a sentence in AGENTS.md or is deliberately left to the spec

## 4. Integration

- [x] 4.1 Run `nu tests/run-tests.nu` inside the digest-pinned `ghcr.io/nushell/nushell:0.115.1-alpine@sha256:…` image and verify it passes (no tool code changed, so this guards that the AGENTS.md and README edits did not break the release-marker and example checks)
- [x] 4.2 Run `openspec validate add-dependency-updates --strict` and verify it passes

## Workflow follow-up

- After merge, add `nushell-checksum` to the `main` ruleset's required checks.
- Install the Mend Renovate App on `bond-os/nexus-cleanup` only and confirm the Dependency Dashboard issue lists the expected dependencies.
- Archive the change once the first scheduled run has opened its pull requests as specified.
