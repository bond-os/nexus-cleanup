# Spec Delta

## ADDED Requirements

### Requirement: Upgrade a configuration repository

The tool SHALL provide an `upgrade` subcommand that moves every version pin `init` writes, in the
files of a configuration repository that exist, to the tool's own version: image pins in the
pipeline, the Forgejo workflow's release tag, and the schema address in configuration files and
editor settings.

#### Scenario: Older repository upgraded

- **WHEN** `upgrade` is run in a repository written by `init` of an older release
- **THEN** every pin names the running tool's version and each changed file is listed
- **AND** the files are identical to what `init` of the running release writes with the same options

#### Scenario: Pin precision kept

- **WHEN** the pipeline pins the image as `nexus-cleanup:0.1`
- **THEN** after `upgrade` it pins the running release's `X.Y`

#### Scenario: Mirror prefix kept

- **WHEN** the pipeline pins the image as `nexus.corp:5000/bond-os/nexus-cleanup:0.1.0`
- **THEN** after `upgrade` the prefix is unchanged and the tag is the running version

#### Scenario: Digest pin replaced by a tag

- **WHEN** the pipeline pins the image as `nexus-cleanup:0.1.0@sha256:<digest>` or `nexus-cleanup@sha256:<digest>`
- **THEN** after `upgrade` each such pin is the running version's tag, without a digest
- **AND** a warning names each such line and advises re-adding a verified digest
- **AND** the exit code is 0

#### Scenario: Forgejo's Nushell moved with the tool

- **WHEN** the Forgejo workflow installs the x86_64 Nushell binary at an older `NU_VERSION`
- **THEN** after `upgrade` its `NU_VERSION` and `NU_SHA256` are those of the running release's own workflow

#### Scenario: Another Nushell binary left alone

- **WHEN** the Forgejo workflow installs a Nushell binary other than x86_64
- **THEN** `upgrade` leaves `NU_VERSION` and `NU_SHA256` unchanged and says they must be updated by hand

#### Scenario: Look-alikes untouched

- **WHEN** the GitLab pipeline names jobs `nexus-cleanup:dry-run`, `nexus-cleanup:execute` and `.nexus-cleanup:`
- **THEN** `upgrade` leaves those names unchanged

### Requirement: Upgrade is local and contained

`upgrade` SHALL work in the working directory unless another is given, SHALL read and write no
file other than those whose pins it moves, and SHALL need no environment variable or credential
and make no network request. It SHALL list each file it changed and exit 0 whether or not
anything changed. An unknown option or an unusable directory SHALL be a usage error.

#### Scenario: Other files untouched

- **WHEN** the repository holds files `init` does not write, outside `configs/`
- **THEN** `upgrade` neither reads nor changes them

#### Scenario: Nothing to upgrade

- **WHEN** every pin already names the running version
- **THEN** no file is written, the command says nothing was changed, and the exit code is 0

#### Scenario: Unknown option

- **WHEN** `upgrade --execute` is run
- **THEN** the exit code is the usage error code and no file is written
