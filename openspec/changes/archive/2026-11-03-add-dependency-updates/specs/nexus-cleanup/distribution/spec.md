## ADDED Requirements

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

## MODIFIED Requirements

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
