# distribution Specification

## Purpose

Defines how the cleanup tool is versioned, released and packaged for CI operators: how a
version is derived from the project's history, what a release produces, what the published
container image contains and how it may be referenced, and which checks stand between a
change and a published artefact.

## Requirements

### Requirement: Versions derive from commit messages

Release versions SHALL follow semantic versioning and SHALL be derived from the Conventional
Commits messages merged since the previous release: a fix bumps the patch, a feature bumps the
minor, and a breaking change bumps the major. While the version is below 1.0.0 a breaking
change SHALL bump the minor instead. The first release SHALL be 0.1.0.

#### Scenario: First release

- **WHEN** no release exists yet and the first release is made
- **THEN** its version is 0.1.0

#### Scenario: Feature since the last release

- **WHEN** the last release is 0.1.0 and a feature commit has been merged since
- **THEN** the next release is 0.2.0

#### Scenario: Only fixes since the last release

- **WHEN** the last release is 0.2.0 and only fix commits have been merged since
- **THEN** the next release is 0.2.1

#### Scenario: Breaking change before 1.0

- **WHEN** the last release is 0.2.1 and a commit marked as a breaking change has been merged since
- **THEN** the next release is 0.3.0, not 1.0.0

### Requirement: A release is proposed and merged, never automatic

Merging ordinary changes to the main branch SHALL NOT by itself publish a release. The pending
release SHALL be proposed as a reviewable pull request showing the next version and its
changelog entry, and a release SHALL happen only when a maintainer merges that proposal.

#### Scenario: Ordinary merge

- **WHEN** a feature pull request is merged to the main branch
- **THEN** no tag, release or image is published
- **AND** the pending release proposal is created or updated to include the change

#### Scenario: Release proposal merged

- **WHEN** a maintainer merges the release proposal for version 0.2.0
- **THEN** the tag `v0.2.0` and a release with that version's changelog entry are published

#### Scenario: Release proposal is checked like any change

- **WHEN** the release proposal is opened or updated
- **THEN** the same required checks that gate other pull requests run against it

### Requirement: The changelog is maintained in the repository

Each release SHALL add an entry to a changelog file in the repository, generated from the
commit messages included in that release, and the published release notes SHALL match that
entry.

#### Scenario: Changelog entry per release

- **WHEN** version 0.2.0 is released
- **THEN** the changelog file contains a 0.2.0 entry listing the changes included in it

### Requirement: The released tool reports the release version

Every released artefact SHALL identify itself with the version of the release it belongs to,
and that version SHALL be the same everywhere the tool or image exposes one.

#### Scenario: Image and tool agree

- **WHEN** the image tagged `0.2.0` is inspected and the tool inside it is asked for its version
- **THEN** the image's version label and the tool's reported version are both `0.2.0`

### Requirement: Container image is published for each release

Each release SHALL publish a container image at `ghcr.io/bond-os/nexus-cleanup` as a single
multi-platform reference covering `linux/amd64`, `linux/arm64` and `linux/arm/v7`.

#### Scenario: Pull on an arm64 runner

- **WHEN** an arm64 CI runner pulls the image tag of a release
- **THEN** it receives the arm64 variant of that release

### Requirement: Image tags are exact or minor, never floating

Each release `X.Y.Z` SHALL publish the image tags `X.Y.Z` and `X.Y`. The `X.Y` tag SHALL move to
the newest patch release of that minor. No `latest` tag or any other tag that crosses minor
versions SHALL be published, and an `X.Y.Z` tag SHALL never be re-pointed once published.

#### Scenario: Patch release moves the minor tag

- **WHEN** release 0.2.1 is published after 0.2.0
- **THEN** the tag `0.2.1` is published and the tag `0.2` refers to the same image as `0.2.1`
- **AND** the tag `0.2.0` still refers to the 0.2.0 image

#### Scenario: No floating tag

- **WHEN** an operator tries to pull `ghcr.io/bond-os/nexus-cleanup:latest`
- **THEN** no such tag exists

### Requirement: Image entrypoint runs the tool in its safe default

The image's default entrypoint SHALL be the tool itself, so that arguments given after the image
name are passed to the tool unchanged and a run without the execute flag is a dry run. The
image SHALL NOT set any environment variable or default argument that changes the tool's
behaviour.

#### Scenario: Arguments follow the image name

- **WHEN** an operator runs the image with `--pattern 'yum-proxy-*'` and the connection settings in the environment
- **THEN** the tool performs a dry run over the matching repositories and writes the report to standard output

#### Scenario: Exit codes pass through

- **WHEN** the image is run with no repository selection
- **THEN** the container exits with the tool's usage error code
- **AND** standard output is empty

### Requirement: Tool is runnable from a shell inside the image

The image SHALL provide the tool as a command named `nexus-cleanup` on the executable search
path, so CI systems that replace the entrypoint with a shell can invoke it by name with the same
arguments, output and exit codes as the default entrypoint.

#### Scenario: Entrypoint cleared by the CI system

- **WHEN** a CI job runs the image with its entrypoint cleared and executes `nexus-cleanup --pattern 'yum-proxy-*'` from a shell script
- **THEN** the run behaves exactly as it would through the default entrypoint

### Requirement: Workspace mounts do not hide the tool

The tool SHALL be installed outside the image's working directory, and the working directory
SHALL be empty, so that mounting a CI workspace at the working directory leaves the tool intact
and relative output paths land in the mounted workspace.

#### Scenario: Workspace mounted at the working directory

- **WHEN** a CI job mounts its workspace at the image's working directory and runs the tool with `--summary-out summary.json`
- **THEN** the tool runs normally
- **AND** `summary.json` is written into the mounted workspace

### Requirement: Image runs without root privileges

The image SHALL declare a numeric, non-zero default user, so that a runtime can verify it is not
root without starting it. The tool SHALL run under any user and group ID the runtime assigns,
including an arbitrary UID with group 0. It SHALL also run with a read-only root filesystem, no
Linux capabilities and privilege escalation disabled. Apart from the output locations the
operator names, it SHALL need no writable path.

#### Scenario: Kubernetes requires a non-root user

- **WHEN** a pod runs the image with `runAsNonRoot: true` and sets no `runAsUser`
- **THEN** the container is admitted and the tool starts

#### Scenario: Arbitrary user ID

- **WHEN** the image is run as a user ID that exists nowhere in the image, with group 0, a read-only root filesystem, every capability dropped and privilege escalation disabled
- **THEN** `--version` prints the release version and exits 0
- **AND** a run with no repository selection exits with the tool's usage error code

#### Scenario: Rootless runtime writes into the mounted workspace

- **WHEN** a rootless Podman job mounts a workspace owned by the invoking host user at the working directory, maps that user into the container as documented, and runs the tool with `--summary-out summary.json`
- **THEN** `summary.json` is written into the workspace and is owned by the invoking host user

### Requirement: Image contains only the runtime and the tool

The image SHALL consist of the official Nushell image at the project's pinned version plus the
tool's entrypoint and module, including the templates the module's repository initialisation
writes, and SHALL NOT contain the tests, fixtures, development tooling, planning artefacts or any
credential.

#### Scenario: Image contents

- **WHEN** the image's filesystem is listed
- **THEN** it holds the Nushell runtime and the tool's entrypoint and module
- **AND** no test, fixture, recording tool, OpenSpec file or credential is present

#### Scenario: Templates present, development tools absent

- **WHEN** the image's filesystem is listed
- **THEN** the templates used by `init` are present inside the tool's installation directory
- **AND** neither the example renderer nor the schema generator is present

### Requirement: Images carry verifiable provenance

Each published image SHALL carry a build provenance attestation that ties it to the source
revision and workflow that built it, verifiable by anyone with read access to the image.

#### Scenario: Verify a pulled image

- **WHEN** an operator verifies the attestation of a release image against the repository
- **THEN** verification succeeds and names the release's source revision

### Requirement: Nothing is published unless the release passes its gates

An image SHALL be pushed only after the full test suite has passed on the release revision and
the built image has passed a smoke check of its entrypoint, its version, its exit codes and the
inert import of the module. A failed gate SHALL publish no image tag.

#### Scenario: Smoke check fails

- **WHEN** the built image's reported version does not match the release version
- **THEN** no image tag for that release is pushed
- **AND** the release workflow fails visibly

#### Scenario: Gates pass

- **WHEN** the tests and every smoke check pass
- **THEN** the image is pushed with its release tags and its attestation

### Requirement: Image build is checked before merge

Every pull request SHALL build the image and run the same smoke check as a release, without
publishing anything, so a change that breaks the image is caught before it reaches a release.

#### Scenario: Pull request breaks the image

- **WHEN** a pull request changes the image so that the tool no longer starts
- **THEN** the pull request's image check fails
- **AND** nothing is pushed to the registry

### Requirement: Commit messages are validated

Every commit in a pull request SHALL be checked against the Conventional Commits format before
merge, and a non-conforming commit SHALL fail the check with a message identifying it.

#### Scenario: Non-conforming commit

- **WHEN** a pull request contains a commit whose message is `init - openspec`
- **THEN** the commit check fails and names that commit

#### Scenario: Conforming commits

- **WHEN** every commit in a pull request has a message such as `feat: add version flag` or `ci: pin actions`
- **THEN** the commit check passes

### Requirement: Validated commits reach the main branch unchanged

Pull requests SHALL be merged only by rebasing their commits onto the main branch, so that the
commits that reach the main branch, and from which versions and changelogs are derived, are
exactly the ones the commit check validated. Merging SHALL require the commit check, the test
suite, the image check and the Nushell checksum check to pass.

#### Scenario: Multi-commit pull request merged

- **WHEN** a pull request with three validated commits is merged
- **THEN** the main branch gains those three commits with their messages unchanged
- **AND** no merge commit or squashed commit is created

#### Scenario: Required check failing

- **WHEN** any of the commit check, the test suite, the image check or the Nushell checksum check fails on a pull request
- **THEN** the pull request cannot be merged

### Requirement: Repository initialisation from the image

Running `init` through the image SHALL write the configuration repository into the mounted
working directory, under the same user mapping the image already documents for output files,
and SHALL need no writable path outside it.

#### Scenario: Initialise into a mounted workspace

- **WHEN** an operator runs the image with an empty host directory mounted at the working directory, the documented user mapping, and the arguments `init --ci gitlab`
- **THEN** the repository files appear in the host directory, owned by the invoking host user
- **AND** the exit code is 0

#### Scenario: Read-only root filesystem

- **WHEN** the same command runs with a read-only root filesystem, an arbitrary user ID with group 0 and every capability dropped, with a writable workspace mounted
- **THEN** the files are written into the workspace and the exit code is 0

#### Scenario: Pins match the image

- **WHEN** `init` is run from the image tagged `0.3.0`
- **THEN** the written pipeline references `ghcr.io/bond-os/nexus-cleanup:0.3.0` and the schema at tag `v0.3.0`

### Requirement: Dependency updates are proposed, never merged automatically

New releases of the project's pinned external components SHALL be proposed as pull requests on
a regular schedule. An update pull request SHALL pass the same required checks as any other
change and SHALL reach the main branch only when a maintainer merges it; no update SHALL be
merged automatically, whatever its kind or size.

#### Scenario: New release of a pinned action

- **WHEN** a pinned GitHub Action publishes a new release
- **THEN** a pull request moving its pin is opened by the next scheduled update run
- **AND** the pull request stays open until a maintainer merges it, even when every check passes

#### Scenario: Update pull request is checked like any change

- **WHEN** an update pull request is opened or updated
- **THEN** the commit check, the test suite, the image check and every other required check run against it

### Requirement: New npm releases are proposed only after a waiting period

A new release of an npm package SHALL be proposed only once it has been published for at least
three days.

#### Scenario: Fresh npm release

- **WHEN** a new commitlint version was published one day ago
- **THEN** no update pull request for it is opened yet

#### Scenario: Release past the waiting period

- **WHEN** a new commitlint version was published four days ago
- **THEN** the next scheduled update run proposes it

### Requirement: The Nushell runtime moves as one change

An update of the Nushell runtime SHALL move every place the project pins it — the image's base,
the CI test environment, the documented version floor, the README's unreleased-revision command
and the Nushell version the generated Forgejo pipeline installs — in one pull request, so the
project never states two runtime versions at once.

#### Scenario: Nushell release proposed

- **WHEN** a new Nushell release is proposed
- **THEN** a single pull request changes every Nushell pin to that release
- **AND** no Nushell pin is left at the previous release on that branch

#### Scenario: Generated example stays in step

- **WHEN** the Nushell update pull request changes the Forgejo template
- **THEN** it changes the committed Forgejo example identically, so the example check passes

### Requirement: A runtime update is release-visible

A Nushell runtime update, including a refresh of the base image's digest alone, SHALL be committed
as a fix, so that it appears in the changelog and leads to a patch release. Updates of CI actions and of maintenance command-line tools SHALL be committed
as CI changes, which the changelog hides, because they change nothing an operator runs.

#### Scenario: Nushell update merged

- **WHEN** the Nushell update pull request is merged after release 0.3.0
- **THEN** the pending release proposal is for 0.3.1
- **AND** its changelog entry lists the Nushell update

#### Scenario: Action update merged

- **WHEN** an action update pull request is merged
- **THEN** the changelog gains no entry for it

### Requirement: The image's Nushell base is pinned by digest

The image's base and the CI test environment SHALL reference the Nushell image by version tag and
content digest together, so a re-pushed tag cannot change what is built or tested. Documentation
and the `init` templates SHALL state the version only.

#### Scenario: Upstream re-pushes the pinned tag

- **WHEN** the Nushell image tag the project pins is re-pushed upstream with new content
- **THEN** one update pull request changes the digest in the image's base and the CI test environment and nothing else
- **AND** it is committed as a fix

#### Scenario: Publish re-run builds the same base

- **WHEN** a failed release publish is re-run after the upstream tag was re-pushed
- **THEN** the image is built on the same base content as the first attempt

#### Scenario: Documentation stays readable

- **WHEN** the README, AGENTS.md or a template names the Nushell image or version
- **THEN** it carries no digest

### Requirement: Release-managed pins and recorded data are not dependency updates

The dependency updater SHALL NOT change the tool's own version references — its image tag and its
schema release tag, wherever they appear — nor recorded test fixtures, planning artefacts, or any
pin inside the `init` templates and generated examples other than the Nushell version.

#### Scenario: Tool image pin in the README

- **WHEN** the README references `ghcr.io/bond-os/nexus-cleanup:0.3.0`
- **THEN** no update pull request changes that reference

#### Scenario: Package names inside fixtures

- **WHEN** a recorded npm fixture lists a package version that has a newer release
- **THEN** no update pull request changes the fixture

#### Scenario: Operator-owned pins in a template

- **WHEN** a template pins a container image or action for the generated pipeline to use
- **THEN** no update pull request changes that pin

### Requirement: The generated pipeline's Nushell download is verified before merge

Every pull request SHALL download the Nushell release asset that the Forgejo template installs and
verify it against the checksum the template pins, so that a version and checksum that disagree
fail the pull request instead of every generated Forgejo pipeline.

#### Scenario: Version moved without its checksum

- **WHEN** a pull request changes the template's Nushell version but not its checksum
- **THEN** the checksum check fails and names the version and the expected checksum

#### Scenario: Version and checksum agree

- **WHEN** the template's checksum is that of the asset for its Nushell version
- **THEN** the checksum check passes
