## Why

Running the tool outside CI means holding a Nexus password in the shell: exported by hand,
sourced from a plaintext file, or typed into history. Both audiences do it — developers of this
repository recording fixtures from the reference instance, and operators checking what an edited
configuration file would do before pushing it. [varlock](https://varlock.dev) keeps those values
in a committed, typed `.env.schema` with secrets resolved from a password manager, the OS
keychain or device-local encryption, and injects them into one command without the tool knowing.

## What Changes

- **Operators: `init --env varlock` writes varlock files, on request only.** Like `--editor`,
  the flag is optional and absent by default; `init` without it writes exactly what it writes
  today. With it, `init` also writes:
  - `.env.schema` declaring `NEXUS_URL` (required, typed as a URL, **no value** — there is no
    placeholder to forget, and varlock stops before the tool starts), `NEXUS_USERNAME` (not
    sensitive) and `NEXUS_PASSWORD` (sensitive, required), with comments showing where a
    password may come from: `keychain()`, `varlock(prompt)` or a secret-manager plugin.
  - `.gitignore` ignoring varlock's value files — `.env`, `.env.local`, `.env.*.local` — so a
    password in `.env.local` cannot be committed by accident. Tracked per-environment files such
    as `.env.production` stay committable.

  Both are protected like every other `init` file: an existing one is listed and nothing is
  written unless `--force` is given, which overwrites and never merges. An unknown value is a
  usage error listing the choices.
- **Local runs are one configuration file at a time.** The README shows
  `varlock run -- docker run --rm -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD
  -v "$PWD/configs:/work/configs:ro" ghcr.io/bond-os/nexus-cleanup:X.Y.Z --config configs/x.yaml`.
  The report goes to standard output; nothing is written into the mount, so no `--user` mapping
  is needed. Running every file stays the pipeline's job: `ci/run-configs.sh` is not adapted for
  local use. The command's image pin carries a release marker and is the only pin on its line.
  The section sits next to "Configuration files" and says three more things: a Nexus on the
  operator's own machine is `host.docker.internal` from inside the container, not `localhost`
  (on Linux with `--add-host=host.docker.internal:host-gateway`); a file that sets `summary-out`
  needs the writable mount from "In a container"; and varlock's precedence, in which an exported
  variable beats every file.
- **The README shows per-environment files** — `@currentEnv` with tracked `.env.staging` and
  `.env.production` holding each instance's URL — as the varlock counterpart of the existing
  "one set of files against staging and production" layering. `init` does not write them.
- **Developers: `.env.schema` replaces `.nexus.env.example`** in this repository, declaring the
  same three variables with the reference instance's URL as the default. Real values move to a
  gitignored `.env.local` or a resolver; fixtures are recorded with
  `varlock run -- nu tools/record-fixtures.nu …`. `.gitignore` gains varlock's value files and
  keeps ignoring `.nexus.env`, so a leftover one still cannot be committed.
- **varlock stays optional and outside the tool.** The tool reads only its process environment,
  as now; exporting the variables keeps working everywhere. AGENTS.md records varlock as an
  external wrapper — like Docker, not a dev tool the project writes — so the "Nushell for tests
  and dev tools" rule does not apply to it, and nothing of it may enter the image.
- **The example trees show it.** `tools/render-examples.nu` passes `--env varlock`, so every
  `examples/<system>/` holds the two files and the README can link them.

Non-goals: the tool reading `.env` files itself; varlock in the image or in any generated
pipeline (CI systems inject secrets themselves); a local loop over all configuration files;
any other environment tool.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `nexus-cleanup/config-repository`: a new requirement for environment-tool support on request —
  the `--env` option, its one choice `varlock`, the two files and their content guarantees (no
  URL value, the password sensitive, value files ignored), the usage error for an unknown
  choice, and the same protection of existing files as every other file `init` writes.

## Impact

- **Code**: `nexus-cleanup/scaffold.nu` (argument parsing, file selection),
  `tests/test-scaffold.nu`.
- **Templates**: new `nexus-cleanup/templates/env/varlock/` with `.env.schema` and `.gitignore`.
- **Generated**: `examples/<system>/` re-rendered by `tools/render-examples.nu`;
  `tests/test-examples.nu` must still pass.
- **This repository**: `.env.schema` added, `.nexus.env.example` removed, `.gitignore`
  extended; `tools/record-fixtures.nu` header comment; AGENTS.md "Runtime", "Re-recording
  fixtures" and the `init` decisions (the template's `.gitignore` and its rendered copies are
  live in this repository by design).
- **Docs**: README "Getting started" (`--env`), a new "Running locally" section,
  `x-release-please` marker on the local-run command.
- **Dependencies**: none for the tool or the image. varlock is an optional operator and
  developer install; the version the schema was checked with is recorded in the README, and
  Renovate does not track it.
