## MODIFIED Requirements

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

## ADDED Requirements

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
