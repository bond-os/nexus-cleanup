## Why

Every CI example today checks the tool's source into the consumer's pipeline and runs it from
the stock Nushell image, so what a scheduled cleanup actually runs is "whatever commit got
checked out". For a tool whose failure mode is mass deletion, operators need a versioned,
reproducible artefact they can pin and read a changelog for — and the project needs a release
process that produces one without hand-maintained version numbers.

The existing `Containerfile` is not fit to publish as-is: it installs the tool under `/work`,
which is exactly where `examples/jenkins/Jenkinsfile.sh` mounts the job workspace, so the mount
would hide the tool.

## What Changes

- **Release automation with release-please.** Conventional commits merged to `main` keep a
  release PR open with the next version and a `CHANGELOG.md` entry; merging it tags `vX.Y.Z`
  and publishes a GitHub Release. The first release is `0.1.0`, and while the version is below
  1.0 a breaking change bumps the minor, not the major. release-please runs on a short-lived,
  narrowly scoped GitHub App token so that its release PR runs the normal checks. The App's key
  is readable only from `main`, and rulesets keep the App from landing code on `main` or
  rewriting a published release.
- **Published container image** at `ghcr.io/bond-os/nexus-cleanup`, built in the same workflow
  run that creates the release, for `linux/amd64`, `linux/arm64` and `linux/arm/v7`, tagged
  `X.Y.Z` and `X.Y` only — deliberately **no `latest`** — with OCI labels and a build
  provenance attestation. The image is pushed only after the test suite and an image smoke test
  pass.
- **Image layout fix.** The tool moves to `/opt/nexus-cleanup`, a `nexus-cleanup` launcher goes
  on `PATH` and becomes the entrypoint, and `/work` stays an empty working directory. The same
  image then works both as `docker run IMAGE --pattern …` and in CI systems that clear the
  entrypoint and run `nexus-cleanup …` from a shell.
- **The image runs without root.** It declares a numeric non-root user (`1000:1000`), so a
  Kubernetes pod with `runAsNonRoot` admits it without extra configuration. The tool runs under
  any UID, with a read-only root filesystem and no capabilities, so OpenShift's arbitrary UIDs
  and rootless Podman or Docker work too. The examples and README say which flags make the CI
  workspace writable under each runtime, and the image check runs a rootless Podman pass.
- **The tool knows its version.** A single version constant in the module, rewritten by
  release-please, feeds a new `--version` flag, a `tool_version` field at the end of the report's
  aggregate block, and the image's version label.
- **Commit message checks.** Every commit in a pull request is validated against Conventional
  Commits with commitlint (`@commitlint/config-conventional`), because those messages are what
  release-please turns into versions and changelog entries.
- **Rebase merge only.** The repository is configured so that pull requests land by rebase,
  every PR commit reaches `main` as written, and the checks above are required.
- **Examples and README switch to the published image**, pinned to an exact release, and no
  longer need the tool's source in the consumer's checkout.
- **AGENTS.md narrows the Nushell-only rule** to the shipped tool and its tests; maintenance
  automation (release, commit checks, image build) uses established third-party tools,
  configured rather than written.

Non-goals: publishing to registries other than GHCR, signing images with cosign, a
`--report-out` flag for `docker://` steps in Forgejo, and consolidating the Nushell version pin
that is repeated across the Containerfile, CI and examples.

## Capabilities

### New Capabilities

- `nexus-cleanup/distribution`: how the tool is versioned, released and packaged — version
  derivation from commit messages, the release PR and changelog, the published container image
  (contents, entrypoint, user, platforms, tags, labels, provenance), the gates a release must pass,
  and the commit message checks that feed it.

### Modified Capabilities

- `nexus-cleanup/cli`: adds a version flag that prints the tool's version and exits without
  reading configuration or contacting Nexus.
- `nexus-cleanup/reporting`: the aggregate block also records the version of the tool that
  produced the report.

## Impact

- **Code**: a new `nexus-cleanup/version.nu` exported from `mod.nu`; the entrypoint gains
  `--version`; `report.nu` appends `tool_version`, read from that constant, to the aggregate.
- **Packaging**: `Containerfile` relocates the tool, adds the launcher and declares the numeric
  user; a launcher script and an image smoke-check script shared by pull-request CI and the
  release workflow.
- **CI**: a new release workflow (release-please, image build, smoke test, push, attestation)
  and a commit-check workflow; `tests.yml` additionally builds and smoke-tests the image on
  pull requests without pushing.
- **New config files**: `release-please-config.json`, `.release-please-manifest.json`,
  `.commitlintrc.yaml`, and the generated `CHANGELOG.md`.
- **Repository administration (manual, one-time, before this change merges)**:
  - a private GitHub App with contents and pull-requests write access, installed on this repo
    only;
  - its id and private key stored as secrets of a `release` Environment restricted to `main`,
    not as repository secrets;
  - a ruleset on `main` with no bypass actors, requiring a pull request, rebase merge only and
    the checks;
  - a tag ruleset making `v*` tags creatable only by the App and never updatable or deletable;
  - release immutability enabled.

  The release workflow runs on the push that merges this change, so all of this must exist
  first.
- **History**: none rewritten. The non-conventional `Initial commit`, `init - openspec` and PR
  #1's merge commit are already on `main`. The commit check only covers a pull request's own
  commits, and release-please skips messages it cannot parse.
- **Docs**: `README.md` (image usage, pinning, `--version`, `tool_version`, CI examples table),
  `AGENTS.md` (layout, the narrowed Nushell rule, release process, no `latest`, the App's trust
  boundary and key rotation), and all four CI examples.
- **Compatibility**: the report aggregate gains one field; records and CSV columns are
  unchanged. Anyone who built the old image and relied on the tool living in `/work` must
  switch to the `nexus-cleanup` command or the default entrypoint.
