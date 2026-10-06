## 1. Conventions

- [x] 1.1 Rewrite the Nushell-only rule in `AGENTS.md`. Nushell only applies to the shipped tool (`nexus-cleanup.nu`, `nexus-cleanup/`, the image contents) and to the tests and `tools/`. Maintenance automation (release, commit checks, image build and smoke) uses established third-party tools, configured rather than written, with shell allowed only as glue around them. Move "write helpers in Nushell" under the tool, note that the global `uv` convention applies again if a Python-based maintenance tool is ever adopted, and keep the "No Python, no `uv`" rationale for the tool. Verify by reading that the Runtime section and the "No Python, no `uv`" section no longer contradict each other and that the boundary names all three areas.
- [x] 1.2 Add a "Commits and merging" section to `AGENTS.md`. It covers Conventional Commits as checked by commitlint `config-conventional`, rebase merge only, why squash is not used (release-please reads every commit), and an optional local `commit-msg` hook using `npx commitlint --edit`. Verify that every commit on this branch except `init - openspec` passes `npx --yes -p @commitlint/cli -p @commitlint/config-conventional commitlint --extends @commitlint/config-conventional --from main --to HEAD`, and that `init - openspec` fails it.

## 2. Tool version

- [x] 2.1 Write failing tests in `tests/test-version.nu`. `VERSION` is a semver string exported by `use nexus-cleanup`. `nu nexus-cleanup.nu --version` prints exactly `VERSION` plus a newline and exits 0 with no `NEXUS_URL`, no credentials and no selection. `--version --execute --pattern x` also prints only the version, exits 0 and makes no request (with `NEXUS_URL` unset, any attempt to enumerate would exit 2 instead).
- [x] 2.2 Add `nexus-cleanup/version.nu` with `export const VERSION = "0.0.0" # x-release-please-version` and export it from `mod.nu`. Add `--version` to the entrypoint, handled before `config resolve`. Verify the tests in 2.1 pass and that `nu -c 'use nexus-cleanup'` still prints nothing.
- [x] 2.3 Write failing tests in `tests/test-report.nu`:
  - the aggregate's last field is `tool_version` and equals `VERSION`, for both a populated run and the empty-selection run;
  - `--summary-out` carries it;
  - the CSV header is unchanged.

  Then append `tool_version` in `report summary` and verify the tests pass.
- [x] 2.4 Document `--version` in the options table and `tool_version` in the report section of `README.md`. Add `version.nu` to the Layout block in `AGENTS.md`. Verify the README option table matches `nu nexus-cleanup.nu --help`.

## 3. Container image

- [x] 3.1 Add the launcher `packaging/nexus-cleanup`: a `#!/usr/bin/env nu` script with `def --wrapped main [...args] { exec nu /opt/nexus-cleanup/nexus-cleanup.nu ...$args }`.
- [x] 3.2 Rewrite `Containerfile`:
  - same pinned base, `ARG VERSION`;
  - copy the entrypoint and module to `/opt/nexus-cleanup/` and the launcher to `/usr/local/bin/nexus-cleanup` with `--chmod=0755`;
  - `WORKDIR /work`, `ENTRYPOINT ["/usr/local/bin/nexus-cleanup"]`;
  - OCI labels `org.opencontainers.image.{source,version,licenses,title,description}`, with version taken from `VERSION`;
  - no `RUN` step.

  Add a `.dockerignore` allow-list admitting only `nexus-cleanup.nu`, `nexus-cleanup/` and `packaging/`. Verify `docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 .` succeeds without QEMU installed.
- [x] 3.3 Write `.github/scripts/image-smoke.sh IMAGE EXPECTED_VERSION` implementing every check in the design's smoke table. Verify:
  - it passes against a locally built image (`docker build --build-arg VERSION=0.0.0 -t nexus-cleanup:smoke .`);
  - it fails when run with a wrong expected version;
  - it fails against the current `main` image, whose tool is under `/work`.
- [x] 3.4 Confirm on 0.115.1 inside the image what was verified on 0.116.0:
  - flags pass through unparsed, `--help` shows the tool's help, exit code 2 propagates;
  - arguments with spaces, quotes and the empty string arrive intact;
  - stderr stays separate from stdout.

  Add an argument round-trip case to the smoke script if any of these is not already covered.
- [x] 3.5 Update the README "In a container" section to use the published image. Show:
  - pinning `X.Y.Z` (or a digest);
  - that no `latest` exists, and why;
  - the `nexus-cleanup` command for entrypoint-cleared CI;
  - `gh attestation verify`;
  - the `/work` working directory.

  Keep the stock-image-plus-checkout variant for unreleased revisions. Verify every command in the section runs as written against the locally built image.
- [x] 3.6 Add `USER 1000:1000` to `Containerfile`, before `WORKDIR`, with a comment saying why it is numeric (`runAsNonRoot`) and explicit (not inherited from upstream). The file stays `COPY`-only. Verify:
  - `docker image inspect --format '{{.Config.User}}'` prints `1000:1000`;
  - `/work` is still `1000:1000` and empty;
  - the existing smoke checks pass.
- [x] 3.7 Extend `.github/scripts/image-smoke.sh` with the three new rows of the design's smoke table:
  - the image config `User` is numeric and its uid is not `0`;
  - an arbitrary UID with group 0, `--read-only`, `--cap-drop ALL` and `--security-opt no-new-privileges` runs `--version` and the no-selection usage error;
  - a `--user "$(id -u):$(id -g)"` mount of a non-world-writable directory receives a `--summary-out` file owned by the caller.

  Keep the existing `chmod 0777` case. Make the container engine a parameter (default `docker`). Verify:
  - each new check fails against an image built without `USER 1000:1000`, or explain why it cannot;
  - the whole script passes against the image from 3.6.
- [ ] 3.8 Run the smoke script a second time in the `image` job (see 4.1) under rootless Podman on `ubuntu-24.04`. Load the amd64 image with `docker save | podman load`, and add `--userns=keep-id` to `--user` for the workspace case (`keep-id` alone runs the image's uid, not the caller's). Verify:
  - the Podman pass runs rootless (`podman info` reports `rootless: true`);
  - it passes on this change's PR.

  If it contradicts a rootless row of the design's user matrix, update the matrix and the examples to match what was observed.
- [x] 3.9 Record in `AGENTS.md`, under the deliberate exceptions, that the image declares a numeric `USER 1000:1000`, and why: `runAsNonRoot` cannot verify a named user, and inheriting the user would let upstream change it. Also record that `/work` is deliberately not made group-0-writable, because that would need `RUN` or a non-empty `/work`, and every runtime that uses `/work` mounts over it. Verify by reading that a future agent could not "simplify" either point away without contradicting the recorded reason.

## 4. Pull request checks

- [ ] 4.1 Extend `tests.yml`:
  - add a `workflow_call` trigger;
  - add an `image` job that builds all three platforms without pushing, loads `linux/amd64` with `VERSION` read from `version.nu`, and runs the smoke script;
  - pin every new action by SHA with a version comment.

  - run the smoke script under Docker and, per 3.8, under rootless Podman.

  Verify both jobs pass on the pull request for this change.
- [x] 4.2 Add `.commitlintrc.yaml` (`extends: ['@commitlint/config-conventional']`) and `.github/workflows/commits.yml`. The workflow runs `npx -p @commitlint/cli@<exact> -p @commitlint/config-conventional@<exact> commitlint --from <base> --to <head>` on `pull_request`, with a full-history checkout, on the runner's preinstalled Node. It uses exact npm versions because the wagoid action's Docker Hub image tag can be re-pointed. Verify it fails on a throwaway PR containing a non-conventional commit, naming that commit, and passes on this change's PR.

## 5. Release automation

- [x] 5.1 Add `release-please-config.json` and `.release-please-manifest.json`:
  - one package `.` with `release-type: simple`, `bump-minor-pre-major: true`, `include-v-in-tag: true`, `initial-version: 0.1.0`;
  - `extra-files` naming `nexus-cleanup/version.nu` (generic);
  - `changelog-sections` showing `feat`/`fix`/`perf`/`revert` and hiding the rest.

  Verify against release-please's source that:
  - with no previous release, `initial-version` sets the first version;
  - the `simple` type never creates `version.txt` (`createIfMissing: false`).

  The token-based dry run was skipped by decision, because it would hand a GitHub token to a downloaded package; 8.1 checks the real release PR instead. If 8.1 does not propose `0.1.0`, fall back to `release-as` as the design describes.
- [ ] 5.2 Write `.github/workflows/release.yml` (push to `main`) with three jobs:
  - `release-please`:
    - declares `environment: release`;
    - mints its token with `actions/create-github-app-token` from `RELEASE_APP_CLIENT_ID` / `RELEASE_APP_PRIVATE_KEY`, passing `permission-contents: write` and `permission-pull-requests: write` explicitly and no `owner`/`repositories`, so the token is limited to this repository;
  - `tests`, calling `./.github/workflows/tests.yml` when `release_created`;
  - `publish`, which asserts that `version.nu` equals the `version` output, builds three platforms, loads amd64, smokes, then pushes `X.Y.Z` and `X.Y` via `docker/metadata-action` with `flavor: latest=false` and runs `actions/attest-build-provenance` with `push-to-registry: true`.

  Give each job least-privilege `permissions`, pass release-please outputs to `run:` steps only through `env:`, and pin every action by SHA. Verify with `actionlint`. Also verify:
  - `grep -n '\${{ *steps\.' .github/workflows/release.yml` matches no `run:` body;
  - on a push without a release, only the `release-please` job runs.
- [x] 5.3 Document the release process in `AGENTS.md`:
  - release PR flow;
  - versioning before 1.0;
  - image tags and the no-`latest` decision, with its rationale;
  - why publishing is gated on `release_created` rather than tag push;
  - the version source of truth;
  - the GitHub App's trust boundary: the `release` environment and why the secrets are not repository secrets, the App's and the token's permissions, no bypass on `main`, the tag ruleset and release immutability, and what a stolen key can and cannot do;
  - key rotation (yearly and on maintainer departure; add the new key, update the secret, revoke the old key) and the incident response for a leaked key;
  - both rulesets, flagged as security controls that must not gain bypass actors;
  - re-running a failed `publish`, and fixing a bad release with a new patch release because releases are immutable.

  Verify by reading that each decision in the design's Decisions section that a future agent might "fix" is recorded with its reason.

## 6. CI examples

- [x] 6.1 Switch the GitLab example to `ghcr.io/bond-os/nexus-cleanup:0.1.0` with `entrypoint: [""]`, `GIT_STRATEGY: none` and `nexus-cleanup …` in both jobs. Verify the file with `glab ci lint`, or by review against the GitLab CI schema.
- [x] 6.2 Switch both Jenkins examples to the release image:
  - the Docker Pipeline plugin variant gets `skipDefaultCheckout()`, `args '--entrypoint='` and `sh 'nexus-cleanup …'`;
  - the plain `sh` variant uses `docker run` with the default entrypoint and keeps the workspace mount.

  Verify the `sh` variant's `docker run` lines work against the locally built image with `NEXUS_URL` pointing at an unreachable host and dummy credentials, expecting exit 3, empty stdout and the cause on stderr.
- [ ] 6.3 Change the Forgejo example to fetch the tool with a shallow `git clone --branch v0.1.0` of this repository instead of assuming it is in the consumer's checkout, keeping the node image and the checksum-verified Nushell install. Verify the clone command and the tool invocation by running them in `node:24-bookworm` once `v0.1.0` exists.
- [x] 6.4 Update the README CI table ("Runs in" column, entrypoint notes). In every example, state that the pinned version is bumped deliberately after reading `CHANGELOG.md`. Verify `grep -rn '0.115.1-alpine' examples/` matches only the Forgejo Nushell install comment.

- [x] 6.5 Document rootless and cluster runtimes:
  - **plain `sh` Jenkins example:** comment that `--user "$(id -u):$(id -g)"` is for rootful Docker only, and name `--userns=keep-id` added to `--user` (Podman) and `--user 0:0` in its place (rootless Docker) as the rootless forms;
  - **Docker Pipeline plugin example:** comment that the plugin's injected `-u` cannot write the workspace under rootless Podman, and name the workaround;
  - **README:** add a short "Rootless and Kubernetes" subsection to "In a container", covering:
    - the image's user;
    - that no `runAsUser` is needed under `runAsNonRoot`;
    - OpenShift's arbitrary UIDs;
    - the per-runtime workspace flags.

  Verify the rootless flags against the 3.8 Podman pass rather than by reasoning.

## 7. Repository administration (maintainer, manual; complete before merging this change)

- [x] 7.1 Rebase the branch onto `origin/main`, so that the "branches up to date" rule accepts it. No reword is needed: `init - openspec` reached `main` through PR #1, and rewording it would mean force-pushing `main`. Verify that `commitlint --from origin/main --to HEAD` (pinned versions) passes for every commit the PR will contain.
- [x] 7.2 Create the GitHub App owned by `bond-os`:
  - private ("Only on this account");
  - webhook disabled;
  - repository permissions Contents and Pull requests set to read and write, and nothing else;
  - installed on `bond-os/nexus-cleanup` only.

  Generate a private key and delete the downloaded `.pem` once 7.3 has stored it. Verify on the installation page that it lists exactly one repository and exactly those two permissions plus Metadata read.
- [x] 7.3 Create the Environment `release` with a deployment branch policy allowing `main` only and no required reviewers. Store `RELEASE_APP_CLIENT_ID` and `RELEASE_APP_PRIVATE_KEY` as **environment** secrets. Verify:
  - `gh secret list --env release` shows both;
  - `gh secret list` (repository level) shows neither;
  - `gh api repos/bond-os/nexus-cleanup/environments/release` reports the branch policy.
- [x] 7.4 Disable squash merging and merge commits, enable release immutability, and add the branch ruleset on `main` with no bypass actors:
  - require a pull request, 0 approvals;
  - rebase merge only;
  - required checks `test`, `image` and `commitlint`, each tied to the GitHub Actions app (`integration_id` 15368);
  - branches must be up to date;
  - no force push or deletion.

  Verify:
  - `gh api repos/bond-os/nexus-cleanup` shows only `allow_rebase_merge: true`;
  - the ruleset lists the pull-request rule and the three checks with an empty bypass list;
  - `gh api repos/bond-os/nexus-cleanup/rules/branches/main` lists `deletion`, `non_fast_forward`, `pull_request` and `required_status_checks`.

  Do not test with a direct push from a feature branch: if the ruleset were wrong, unreviewed commits would land on `main` and start the release workflow.
- [x] 7.5 Add two tag rulesets on `refs/tags/v*`. They must be separate, because a bypass list applies to every rule in its ruleset:
  - "release tags: created by the release App only": restrict creation, with the App (by numeric App ID) as the only bypass actor;
  - "release tags: immutable": restrict updates and deletion, with no bypass actors.

  Verify:
  - both rulesets are listed as `active`;
  - pushing a test tag `v0.0.0-ruleset-check` from a maintainer checkout is rejected, and the tag is then deleted locally.
- [x] 7.6 Verify the environment boundary: on a throwaway branch, push a workflow that declares `environment: release` and only checks whether `RELEASE_APP_CLIENT_ID` is non-empty, without printing it. Confirm the job is refused by the branch policy. Delete the branch.

## 8. First release, end to end

- [ ] 8.1 Merge this change and confirm the release PR:
  - it is opened by the App and proposes `0.1.0`;
  - it carries release-please's `autorelease: pending` label without Issues permission;
  - it updates `CHANGELOG.md`, `.release-please-manifest.json` and `version.nu`;
  - its required checks run and pass.

  If labelling fails for lack of Issues permission, add Issues write to both the App and the token's `permission-issues` input, and record why in `AGENTS.md`.
- [ ] 8.2 Merge the release PR and confirm:
  - tag `v0.1.0` and a GitHub Release exist, and the release is shown as immutable;
  - `ghcr.io/bond-os/nexus-cleanup` has `0.1.0` and `0.1`, and no `latest`;
  - `docker buildx imagetools inspect` lists amd64, arm64 and arm/v7.
- [ ] 8.3 Make the GHCR package public if it was created private, then confirm:
  - `gh attestation verify oci://ghcr.io/bond-os/nexus-cleanup:0.1.0 --repo bond-os/nexus-cleanup` succeeds;
  - an anonymous `docker pull` works;
  - `docker run --rm ghcr.io/bond-os/nexus-cleanup:0.1.0 --version` prints `0.1.0`.
- [ ] 8.4 Run a dry run with the published image against the reference Nexus (`--pattern 'yum-proxy-*'`). Confirm the report's `summary.tool_version` is `0.1.0` and that its decisions match a dry run of `nu nexus-cleanup.nu` from the `v0.1.0` checkout.
