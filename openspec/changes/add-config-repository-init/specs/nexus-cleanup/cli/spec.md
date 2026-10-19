## ADDED Requirements

### Requirement: Init subcommand

The tool SHALL accept `init` as its first argument to select the repository initialisation
subcommand instead of a cleanup run. The subcommand SHALL take effect without any connection
setting or repository selection and SHALL NOT validate cleanup configuration. A repository
named `init` SHALL remain selectable through a pattern or a configuration file.

#### Scenario: Subcommand instead of a run

- **WHEN** the tool is invoked as `init --ci gitlab`
- **THEN** it initialises a configuration repository and performs no cleanup run
- **AND** the absence of `NEXUS_URL` and of a repository selection is not an error

#### Scenario: Run flags are not accepted by init

- **WHEN** the tool is invoked as `init --ci gitlab --execute`
- **THEN** the exit code is the usage error code and no file is written

#### Scenario: Repository named init

- **WHEN** a proxy repository is named `init` and the operator selects it with `--pattern init`
- **THEN** that repository is processed by a cleanup run
