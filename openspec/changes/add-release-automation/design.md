## Context

See `proposal.md` for motivation and `specs/` for the contract. Current state this change
builds on:

- `Containerfile` copies `nexus-cleanup.nu` and `nexus-cleanup/` into `/work` and sets
  `ENTRYPOINT ["nu", "/work/nexus-cleanup.nu"]`. Nothing builds or publishes it.
- `.github/workflows/tests.yml` runs the suite and the inert-import check inside
  `ghcr.io/nushell/nushell:0.115.1-alpine` on pushes to `main` and on pull requests. Actions are
  pinned by commit SHA with the version in a trailing comment.
- The base image is an OCI index for `linux/amd64`, `linux/arm64` and `linux/arm/v7`. The image
  build has no `RUN` step, so buildx can produce every platform without QEMU emulation.
- The entrypoint resolves its modules with `use ./nexus-cleanup/…` relative to the script file.
  Verified on Nushell 0.116.0: a **symlink** to the entrypoint fails with
  `nu::parser::module_not_found`, because Nushell resolves the relative path against the
  symlink's directory, not the target's.
- The repository is public, allows all three merge methods and has no rulesets. `main` already
  holds the tool through PR #1, merged with a merge commit. Its history includes three
  non-conventional messages: `Initial commit`, `init - openspec` and the merge commit itself.
- `report summary` builds the aggregate record in `report.nu`. Its consumers are the JSON report
  and `--summary-out`. CSV carries records only.

## Goals / Non-Goals

**Goals:**

- One workflow run on `main` takes a merged release PR all the way to a tag, a GitHub Release
  and an attested multi-arch image, with no manual step after the merge.
- A single version source in the repository that release-please rewrites and that the tool, the
  report and the image label all read.
- The same image smoke check runs on every pull request and every release, so a release never
  meets a failure mode for the first time.

**Non-Goals:**

- Release-candidate or nightly images. Every published image is a release.
- Automated dependency bumps (Renovate or Dependabot) for actions or the base image.
- Enforcing the commit format locally. A local hook is documented as optional; CI is the gate.

## Decisions

### release-please in manifest mode, `simple` release type

`release-please-config.json` declares one package at `.` with `release-type: simple`,
`bump-minor-pre-major: true`, `include-v-in-tag: true` and `extra-files` naming
`nexus-cleanup/version.nu` for the generic updater. `.release-please-manifest.json` tracks the
released version. The first release is pinned to `0.1.0` through `initial-version`. If
release-please does not propose `0.1.0` for the first release PR, use `release-as: 0.1.0` for
that release only and remove it afterwards.

`changelog-sections` lists `feat`, `fix`, `perf` and `revert` as visible and hides `docs`, `test`,
`ci`, `chore`, `refactor`, `build` and `style`. Operators read the changelog to decide whether to
bump a pinned version, and that question turns on behaviour changes.

*Alternatives considered:*
- semantic-release releases on every qualifying merge, which conflicts with "a release is
  proposed and merged, never automatic".
- git-cliff with hand-pushed tags produces a changelog but not the release PR or the version
  rewrite.
- cocogitto would duplicate commitlint's job and compete with release-please for versioning.

### The version lives in `nexus-cleanup/version.nu`

```
export const VERSION = "0.0.0" # x-release-please-version
```

It is exported from `mod.nu`, so importing it stays inert. The entrypoint's `--version` prints it
before any configuration is resolved. `report summary` appends `tool_version: $VERSION` as the
last aggregate field, reading the constant directly rather than threading it through `run.nu`.

The image's `org.opencontainers.image.version` label is passed in as a build argument read from
the same file, never from the git tag. The release job then asserts that the file's value equals
the release-please `version` output, so a mismatch between tag and file fails the release
instead of shipping.

Between releases, a checkout of `main` reports the last released version. That is acceptable:
only released artefacts are meant to be pinned, and appending a `-dev` suffix would fight the
generic updater.

*Alternative considered:* deriving the version from `git describe` at runtime. Rejected because
the image has no git, and the no-external-binaries rule forbids calling it.

### Image layout: tool in `/opt`, an `exec` launcher on `PATH` as the entrypoint

```
/opt/nexus-cleanup/nexus-cleanup.nu     entrypoint script, unchanged
/opt/nexus-cleanup/nexus-cleanup/       module
/usr/local/bin/nexus-cleanup            launcher (COPY --chmod=0755), also the ENTRYPOINT
/work                                   WORKDIR, empty
```

The launcher is a Nushell script:

```
#!/usr/bin/env nu
def --wrapped main [...args] { exec nu /opt/nexus-cleanup/nexus-cleanup.nu ...$args }
```

`--wrapped` passes every argument through unparsed, and `exec` replaces the process. Standard
output, standard error and the exit code are therefore exactly the entrypoint script's. Verified
on 0.116.0 with:
- flags such as `--execute`;
- `--version` and `--help`;
- exit code 2;
- arguments containing spaces, quotes and the empty string.

The same check must pass on 0.115.1 in the image smoke test.

Using the launcher as the `ENTRYPOINT` gives the default entrypoint and the cleared-entrypoint
case one code path. That is what the spec's "exactly as it would" requires.

*Alternatives considered:*
- A symlink: rejected by the module-resolution finding above.
- A `/bin/sh` `exec` wrapper: it would work, but it makes the image depend on the base image's
  shell when Nushell can do the job.
- Making the entrypoint script resolve modules absolutely: this changes the shipped tool to suit
  one packaging, and would break `nu nexus-cleanup.nu` from a checkout.

### `Containerfile` stays `COPY`-only

The base image stays pinned by tag, as it is today. The build copies the tool, the launcher and
the labels. A `RUN` step would force QEMU for `arm64` and `arm/v7` and slow every build, so any
future need that seems to require one should be questioned first.

The `.dockerignore` (or `.containerignore`) is an allow-list. It admits only the entrypoint, the
module and the launcher, which keeps tests, fixtures, `.nexus.env` and `openspec/` out of the build
context. That enforces "Image contains only the runtime and the tool" at the source rather than
relying on `COPY` lines alone.

### One smoke-check script, two callers

`.github/scripts/image-smoke.sh IMAGE EXPECTED_VERSION` runs against a locally loaded image and
fails on the first broken check:

| Check | Expected |
|---|---|
| `IMAGE --version` | stdout is exactly `EXPECTED_VERSION`, exit 0 |
| `IMAGE` with no arguments and no environment | exit 2, empty stdout |
| entrypoint cleared, `sh -c 'nexus-cleanup --version'` | same as the first check |
| `-v "$tmp:/work"` with `--version` | still runs (the mount does not hide the tool) |
| `--entrypoint nu IMAGE -c 'use /opt/nexus-cleanup/nexus-cleanup'` | no output, exit 0 |
| `ls /opt/nexus-cleanup` inside the image | exactly the entrypoint and the module |
| image label `org.opencontainers.image.version` | `EXPECTED_VERSION` |

None of these checks needs a network or a Nexus. The script orchestrates `docker`, which places
it under the maintenance-tooling side of the AGENTS.md boundary, so bash is appropriate.

The `sh -c` check uses the base image's shell only to imitate a CI runner. The tool itself never
calls it.

### Workflows

```
tests.yml (pull_request, push to main, workflow_call)
  test         suite + inert import, in the pinned Nushell image      (unchanged)
  image        buildx all 3 platforms, no push; load amd64; smoke

commits.yml (pull_request)
  commitlint   every commit in base..head, config-conventional

release.yml (push to main)
  release-please   App token -> opens/updates release PR, or tags + releases
       | if release_created
       v
  tests            uses: ./.github/workflows/tests.yml   (re-run on the release SHA)
       v
  publish          check version.nu == output.version
                   buildx 3 platforms -> load amd64 -> smoke
                   push X.Y.Z and X.Y -> attest-build-provenance (push-to-registry)
```

- **Job permissions.** `publish` uses the job's `GITHUB_TOKEN` with `packages: write`,
  `id-token: write` and `attestations: write`. Only the release-please step uses the App token,
  minted per run with `actions/create-github-app-token` from `RELEASE_APP_CLIENT_ID` and
  `RELEASE_APP_PRIVATE_KEY`.
- **Workflow hygiene.** release-please outputs reach `run:` steps through `env:`, never through
  `${{ }}` interpolated into the script. No workflow uses `pull_request_target`.

### The GitHub App and its trust boundary

The App exists for one reason: pull requests and tags created with `GITHUB_TOKEN` do not
trigger other workflows, so the release PR would never run its required checks. Its private key
is the one long-lived credential in this design. The design limits both who can read the key and
what a token minted from it can do.

```
 RELEASE_APP_PRIVATE_KEY
   | readable only by jobs on main that declare `environment: release`
   v
 create-github-app-token  --> installation token: 1 hour, this repo only,
   |                          contents + pull-requests (write), nothing else
   v
 release-please: pushes release-please--branches--main, opens the release PR,
                 creates the v* tag and the Release after that PR is merged
```

**1. The secrets live in an Environment, not in the repository.** Both secrets are stored in
an Environment named `release`, whose deployment branch policy allows `main` only. The
`release-please` job declares `environment: release`. A workflow pushed on any other branch,
or run for a pull request, cannot read the key, even when its author has write access.

There are no required reviewers on the environment, because every push to `main` runs the job.

*Alternative considered:* repository secrets. Rejected because any workflow on any branch can
read them, so write access would be enough to take the key.

**2. The token asks for less than the App holds, and the App holds little.** The App is private
(installable only on `bond-os`), installed on `bond-os/nexus-cleanup` only, and granted Contents
and Pull requests read and write (Metadata read is implicit). `create-github-app-token` passes
`permission-contents: write` and `permission-pull-requests: write` explicitly and is limited to
the current repository. Each token can therefore do no more than this run needs, even if the App
later gains permissions.

Issues write is left out: GitHub's label endpoints accept Pull requests write for PRs. Add it to
both the App and the token only if release-please demonstrably fails to label its PR without it.

**3. `main` accepts changes only through pull requests, and the App cannot bypass that.** See
Repository rules. release-please never pushes to `main`: it pushes its own branch and opens a
PR. So the App needs no bypass on `main`. A stolen key cannot land code on `main`.

**4. Release tags are created only by the App and are immutable once created.** A tag ruleset on
`refs/tags/v*` restricts creation, update and deletion. The App is the only bypass actor, and
only for creation. Release immutability is enabled on the repository, so a published release's
tag and assets cannot be changed afterwards.

Pinned `X.Y.Z` references can therefore never be moved under a consumer. That includes the
Forgejo example's `git clone --branch vX.Y.Z`. A stolen key cannot rewrite an existing release.

**Key handling.** The `.pem` file is deleted locally once stored. The key is rotated yearly and
whenever a maintainer with access leaves. Apps allow two active keys, so rotation means: add the
new key, update the secret, then revoke the old key.
- **Tags.** `docker/metadata-action` with two `type=semver` patterns, `{{version}}` and
  `{{major}}.{{minor}}`, fed the release tag, plus `flavor: latest=false`. Without that flavor
  setting, metadata-action adds `latest` on semver tags.
- **commitlint.** A shell step runs `npx -p @commitlint/cli@<exact> -p
  @commitlint/config-conventional@<exact> commitlint --from <base> --to <head>` on the runner's
  preinstalled Node, with `.commitlintrc.yaml` extending the preset and nothing else. The
  repository gains no `package.json`.

  *Alternative considered:* `wagoid/commitlint-github-action`. Rejected during implementation:
  even when the action is pinned by SHA, it runs `docker://wagoid/commitlint-github-action:<tag>`,
  a Docker Hub tag that can be re-pointed. So the pin does not pin what executes. Published npm
  versions are immutable.
- **Pinning.** Every third-party action is pinned by commit SHA with the version in a comment,
  matching `tests.yml`.

*Alternatives considered:*
- A separate workflow triggered by tag push. This works with the App token, but it adds a
  second entry point: anyone with push access could publish an image by pushing a `v*` tag
  without going through a release PR. Gating `publish` on `release_created` in the same run
  makes the merged release PR the only way to publish.
- A draft GitHub Release that is un-drafted after the image push: this needs
  `force-tag-creation`, plus a second token-scoped step. Deferred unless a failed publish proves
  to be a real problem (see Risks).

### Repository rules

These are configured once by hand and documented in `AGENTS.md`.

The branch ruleset on `main`, with **no bypass actors** (neither the App nor administrators):
- require a pull request before merging, with 0 required approvals, because a sole maintainer
  cannot approve their own PRs;
- allowed merge method **rebase** only;
- required status checks `test`, `image` and `commitlint`, with "require branches to be up to
  date", so the checked commits are the ones that land;
- no force pushes and no deletion.

The tag ruleset on `refs/tags/v*`:
- restrict creation, with the release App as the only bypass actor;
- restrict updates and deletion, with no bypass actors.

Repository settings:
- squash merging and merge commits are turned off, so the merge button offers nothing else;
- release immutability is enabled.

The rulesets carry the security argument in "The GitHub App and its trust boundary". Weakening
any of them, in particular adding a bypass actor on `main`, reopens what that section closes.

### Examples: pin the image, drop the checkout

| Example | Change |
|---|---|
| GitLab | `image: ghcr.io/bond-os/nexus-cleanup:0.1.0` with `entrypoint: [""]`, `script: nexus-cleanup …`, and `GIT_STRATEGY: none` because nothing from the repository is needed |
| Jenkins, Docker Pipeline plugin | the release image, `args '--entrypoint='`, `sh 'nexus-cleanup …'`, and `skipDefaultCheckout()` |
| Jenkins, plain `sh` | `docker run` of the release image with its default entrypoint; the workspace mount stays because `--summary-out` and the report land there |
| Forgejo | stays on a node job image because `upload-artifact` needs node. It replaces "the tool is in your repository" with a shallow `git clone --branch v0.1.0` of this repository, keeping the checksum-verified Nushell install |

Each example states that the pinned version should be bumped deliberately, after reading the
changelog.

## Risks / Trade-offs

- **The release is tagged before the image is pushed.** If `publish` fails, a GitHub Release
  exists without an image. → The release PR already passed `test` and `image` on identical
  content, so a failure here is infrastructure. Re-running the job is idempotent: same tags,
  same digest inputs. The release notes are edited only if a re-run cannot fix it.
- **A new GHCR package may be created private.** → One-time manual step: after the first
  publish, set the package to public and confirm it is linked to the repository. The
  `org.opencontainers.image.source` label provides the link.
- **Non-conventional commits already on `main`.** → They are left as they are: rewording them
  would mean force-pushing `main`. They cannot block a pull request, because the commit check
  covers only `base..head`. release-please skips unparseable messages and still finds the
  `feat:` commits, so the first release is `0.1.0` regardless.
- **The launcher behaviour was verified on 0.116.0, not 0.115.1.** → The smoke check exercises
  every verified property inside the pinned image on the first PR. If `--wrapped` or `exec`
  differ on 0.115.1, revisit before merge.
- **Moving the `X.Y` tag means a consumer on `0.2` picks up `0.2.1` unread.** → Under
  `bump-minor-pre-major`, a patch release contains fixes only. The examples pin `X.Y.Z` anyway,
  and `X.Y` is documented as a convenience.
- **commitlint's `config-conventional` rejects upper-case or sentence-case subjects.** → All
  existing conventional commits already comply. The rule set is the preset's and is not
  customised, so the same check can be run locally.
- **The App's private key is a long-lived secret.** → It is readable only from `main` through
  the `release` environment. The App's reach is limited to this repository, to contents and pull
  requests, and below the rulesets. The key never reaches the image or the publish job.
- **What a stolen key can still do.** It can open junk pull requests, push non-`main` branches,
  and create a *new* `v*` tag and release pointing at code on such a branch. It cannot land code
  on `main`, move or delete an existing release, or publish an image, because `publish` runs only
  from release-please on `main`. → A forged new release is visible on the releases page and
  absent from `CHANGELOG.md` on `main`. Consumers bump pins deliberately after reading the
  changelog. Response: revoke the key, delete the forged release and tag (an administrator can
  delete an immutable release), and rotate.
- **Immutable releases cannot be corrected in place.** A release with wrong content is fixed by
  publishing the next patch release, never by moving its tag. A failed `publish` is unaffected:
  re-running it pushes images and changes no tag.
- **Every push to `main` records a deployment in the `release` environment.** This is
  accepted noise in the Deployments view; it is the cost of branch-restricting the secrets.

## Migration Plan

1. Before merging this change, set up the repository. `release.yml` runs on the very push that
   merges it, so the App must already exist. Set up:
   - the GitHub App;
   - the `release` environment and its secrets;
   - both rulesets;
   - the merge settings;
   - release immutability.
2. Merge this change. The App opens the first release PR, proposing `0.1.0`, and its checks run.
3. Merge the release PR. `release.yml` tags `v0.1.0`, publishes the release and pushes
   `0.1.0` and `0.1`.
4. Make the GHCR package public and verify the attestation:
   `gh attestation verify oci://ghcr.io/bond-os/nexus-cleanup:0.1.0 --repo bond-os/nexus-cleanup`.

**Rollback.** Delete `release.yml`, the `release` environment and the App installation. The
tests, commit checks and rulesets keep working.
Published images and tags are never deleted: consumers may have pinned them.
