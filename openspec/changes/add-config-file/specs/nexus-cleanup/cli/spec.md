## MODIFIED Requirements

### Requirement: Dry run is the default

The tool SHALL run in dry-run mode unless the operator passes an explicit execute flag. In
dry-run mode the tool SHALL perform every read, grouping and ordering step and produce the
full report, and SHALL issue no deletion request of any kind.

#### Scenario: No execute flag given

- **WHEN** the tool is invoked without the execute flag
- **THEN** the report lists the components that would be deleted
- **AND** no deletion request is sent to Nexus
- **AND** the report identifies the run mode as a dry run

#### Scenario: Execute flag given

- **WHEN** the tool is invoked with the execute flag
- **THEN** each component marked for deletion is deleted
- **AND** the report identifies the run mode as an executing run

#### Scenario: Execute flag is not implied

- **WHEN** any other flag or environment variable is set, including verbose or format flags
- **THEN** the run remains a dry run unless the execute flag itself was passed

#### Scenario: Execute is not implied by a configuration file

- **WHEN** the tool is invoked with a configuration file and without the execute flag
- **THEN** the run remains a dry run whatever the file contains

### Requirement: Configuration precedence and validation

The tool SHALL read connection settings from the environment and SHALL let an equivalent
command-line flag override the environment value for the same setting. When a configuration
file is given, its values SHALL sit below both: a flag overrides the file for every setting, and
the environment overrides the file for connection settings. All configuration, from every
source, SHALL be validated before any repository is enumerated, and an invalid value SHALL abort
the run with a message naming the offending setting.

#### Scenario: Flag overrides environment

- **WHEN** `NEXUS_URL` is set in the environment and a URL flag with a different value is passed
- **THEN** the flag's value is used

#### Scenario: Invalid value rejected up front

- **WHEN** a keep count, timeout or retry limit is not a valid positive value
- **THEN** the run aborts with a usage error naming that setting
- **AND** no repository is enumerated

#### Scenario: Flag overrides the configuration file

- **WHEN** a configuration file sets a keep count and a different keep count is passed as a flag
- **THEN** the flag's value is used

#### Scenario: Invalid file value rejected up front

- **WHEN** a configuration file holds an invalid value for any setting
- **THEN** the run aborts with a usage error naming that setting and the file
- **AND** no repository is enumerated

## ADDED Requirements

### Requirement: A deletion cap can be required

The tool SHALL accept a switch that requires a deletion cap. With it, a run — dry or executing —
whose resolved configuration sets neither an absolute nor a proportional cap SHALL be refused
with a usage error naming both cap settings, before any repository is enumerated. The switch
SHALL NOT imply execution and SHALL NOT be settable from a configuration file.

#### Scenario: Cap missing

- **WHEN** the tool is invoked with the require-cap switch and no cap is set by flag or file
- **THEN** the run aborts with a usage error naming the absolute and the proportional cap settings
- **AND** no repository is enumerated

#### Scenario: Cap from the configuration file

- **WHEN** the tool is invoked with the require-cap switch and a configuration file setting `max-deletions: 200`
- **THEN** the run proceeds with a cap of 200

#### Scenario: Dry run also checked

- **WHEN** the tool is invoked with the require-cap switch, without the execute flag, and no cap is set
- **THEN** the run aborts with the same usage error, so a missing cap surfaces in the dry run rather than at execution

#### Scenario: Not a file setting

- **WHEN** a configuration file contains `require-cap: true`
- **THEN** the run aborts with a usage error naming `require-cap` as an unknown key
