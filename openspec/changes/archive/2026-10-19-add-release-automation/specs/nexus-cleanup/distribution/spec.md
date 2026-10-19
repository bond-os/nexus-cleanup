## Purpose

Defines how the cleanup tool is versioned, released and packaged for CI operators: how a
version is derived from the project's history, what a release produces, what the published
container image contains and how it may be referenced, and which checks stand between a
change and a published artefact.

## ADDED Requirements

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
tool's entrypoint and module, and SHALL NOT contain the tests, fixtures, development tooling,
planning artefacts or any credential.

#### Scenario: Image contents

- **WHEN** the image's filesystem is listed
- **THEN** it holds the Nushell runtime and the tool's entrypoint and module
- **AND** no test, fixture, recording tool, OpenSpec file or credential is present

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
suite and the image check to pass.

#### Scenario: Multi-commit pull request merged

- **WHEN** a pull request with three validated commits is merged
- **THEN** the main branch gains those three commits with their messages unchanged
- **AND** no merge commit or squashed commit is created

#### Scenario: Required check failing

- **WHEN** any of the commit check, the test suite or the image check fails on a pull request
- **THEN** the pull request cannot be merged
