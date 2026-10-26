# Tasks

## 1. `init --env varlock`

- [ ] 1.1 Add `ENV_TOOLS` (`varlock: [".env.schema" ".gitignore"]`) to `scaffold.nu`, parse a repeatable `--env` in `scaffold init-args` (duplicates collapse) and plan the `env/<tool>/` area in `scaffold plan`; list `--env` in `scaffold init-help`; verify with tests in `tests/test-scaffold.nu`: no `--env` writes neither file, `--env varlock` writes both and lists them on stderr, `--env dotenv` exits 2 naming `dotenv` and listing `varlock` with nothing written
- [ ] 1.2 Write `nexus-cleanup/templates/env/varlock/.env.schema`: root decorators `@defaultSensitive=false @defaultRequired=false`, `NEXUS_URL` with `@required @type=url` and no value, `NEXUS_USERNAME` with no decorator beyond its description, `NEXUS_PASSWORD` with `@required @sensitive` and no value, comments pointing to `keychain()`, `varlock(prompt)` and secret-manager plugins, and a header saying it is used with `varlock run -- …` locally and never by the pipeline; verify with a test that the file declares exactly those three variables with those decorators and contains no URL, no `=` value and no version number
- [ ] 1.3 Write `nexus-cleanup/templates/env/varlock/.gitignore` with exactly `.env`, `.env.local` and `.env.*.local`; verify with a test asserting its exact content
- [ ] 1.4 Verify with a test that an existing `.gitignore` makes `init --ci gitlab --env varlock` fail listing it with nothing written, and that `--force` overwrites it and leaves an unrelated file untouched

## 2. Examples

- [ ] 2.1 Make `tools/render-examples.nu` pass `--env varlock` and re-render every `examples/<system>/`; verify `tests/test-examples.nu` passes and that the new files carry no release marker and are not listed in `release-please-config.json`
- [ ] 2.2 By hand, in a scratch copy of `examples/gitlab/` initialised as a git repository: `git add .` after creating `.env.local`, `.env.production.local` and `.env.production` stages only `.env.production` and `.env.schema`; with varlock installed as a standalone binary, `varlock load` with nothing set reports `NEXUS_URL` and `NEXUS_PASSWORD` missing, and with values set masks only the password; record the varlock version used

## 3. Operator documentation

- [ ] 3.1 README "Getting started": add `--env varlock` to the options list and the files table, with the advice to leave it out and add the three lines by hand when a `.gitignore` already exists; verify the table matches what `init` writes
- [ ] 3.2 README: a "Running locally" section with the `varlock run -- docker run --rm -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD -v "$PWD/configs:/work/configs:ro" ghcr.io/bond-os/nexus-cleanup:X.Y.Z --config configs/x.yaml` command inside `x-release-please-start-version` / `-end` markers, the `:ro,z` variant for SELinux hosts, the per-environment pattern (`@currentEnv` with tracked `.env.staging` / `.env.production`), the statement that running every file is the pipeline's job, and the varlock version it was checked with; verify the marked block holds one pin per line and that the command, run against the reference instance with a copy of `examples/configs/yum-proxies.yaml`, prints a JSON report

## 4. This repository

- [ ] 4.1 Add a root `.env.schema` (`NEXUS_URL` defaulting to `http://localhost:8081` with `@type=url`, `NEXUS_USERNAME` defaulting to `admin`, `NEXUS_PASSWORD` `@required @sensitive` without value), remove `.nexus.env.example`, and add `.env`, `.env.local`, `.env.*.local` to `.gitignore` while keeping `.nexus.env`; verify `git check-ignore` ignores the three patterns and `.nexus.env` but not `.env.schema`, and that `.dockerignore` still keeps every one of them out of the build context
- [ ] 4.2 Update the `tools/record-fixtures.nu` header and AGENTS.md "Re-recording fixtures" to show `varlock run -- nu tools/record-fixtures.nu …` with exported variables still accepted, and AGENTS.md "Runtime" to record varlock as an optional external wrapper outside the Nushell-only rule that never enters the image; update the Layout tree; verify `grep -rn 'nexus.env.example' .` finds nothing outside `openspec/`
- [ ] 4.3 By hand: `varlock run -- nu tools/record-fixtures.nu --max-pages 1 packer-bases` against the reference instance with the password in `.env.local` or `keychain()` produces no diff under `tests/fixtures/`

## 5. Integration

- [ ] 5.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and verify it passes; verify `.github/scripts/image-smoke.sh` passes against a locally built image, and that `init --ci gitlab --env varlock` run through that image into a mounted empty directory writes both files
- [ ] 5.2 Run `openspec validate add-varlock-support --strict` and verify it passes

## Workflow follow-up

- Commit the `init` option as `feat:`, the repository's own `.env.schema` as `chore:`, and the docs as `docs:`.
- Archive the change after merge.
