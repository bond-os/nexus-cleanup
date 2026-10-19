## ADDED Requirements

### Requirement: Version flag

The tool SHALL accept a version flag that writes the tool's version, and nothing else, to
standard output and exits successfully. The flag SHALL take effect without any connection
setting or repository selection, SHALL NOT validate other configuration and SHALL NOT contact
Nexus.

#### Scenario: Version printed without configuration

- **WHEN** the tool is invoked with only the version flag and no `NEXUS_URL`, credentials or repository selection
- **THEN** standard output contains the version string followed by a newline, such as `0.1.0`
- **AND** the exit code is 0
- **AND** no HTTP request is made

#### Scenario: Version flag with other flags

- **WHEN** the version flag is passed together with other flags, including the execute flag
- **THEN** only the version is printed and the tool exits with code 0
- **AND** no repository is enumerated and nothing is deleted
