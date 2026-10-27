# Spec Delta

## MODIFIED Requirements

### Requirement: Recognised keys

The file SHALL accept exactly these keys: `url`, `username`, `repositories`, `pattern`, `keep`,
`timeout`, `max-attempts`, `format`, `version-scheme`, `scope-from-path`, `from-path`,
`fail-on-skip`, `max-deletions`, `max-deletion-share`, `summary-out`, `allow-hosted` and
`disabled`, plus a `$schema` key, which SHALL be a string and SHALL otherwise be ignored. Any
other key SHALL be refused with a usage error naming the key and the file, before any request
is made.

#### Scenario: Misspelt key refused

- **WHEN** a configuration file contains `keeep: 3`
- **THEN** the run aborts with a usage error naming `keeep` and the file
- **AND** no request is sent to Nexus

#### Scenario: Every recognised key accepted

- **WHEN** a configuration file sets each recognised key to a valid value
- **THEN** the configuration is accepted

#### Scenario: Schema reference ignored

- **WHEN** a configuration file contains `$schema: https://example.invalid/config.schema.json` beside valid settings
- **THEN** the configuration is accepted and the `$schema` value affects nothing
- **AND** no request is made to the referenced address

#### Scenario: Non-string schema reference refused

- **WHEN** a configuration file contains `$schema: 3`
- **THEN** the run aborts with a usage error naming `$schema` and the file

#### Scenario: Hosted opt-in described by the schema

- **WHEN** a configuration file containing `allow-hosted: true` is validated against the schema of a release that includes this change
- **THEN** it is valid
- **AND** `allow-hosted: "yes"` is invalid

#### Scenario: Hosted opt-in from the file

- **WHEN** a configuration file contains `allow-hosted: true` and `repositories: [raw-builds]`, where `raw-builds` is a raw hosted repository
- **THEN** `raw-builds` is processed
- **AND** the run is a dry run unless the execute flag is passed

#### Scenario: Disabled key described by the schema

- **WHEN** a configuration file containing `disabled: true` is validated against the schema of a release that includes this change
- **THEN** it is valid
- **AND** `disabled: "yes"` and `enabled: false` are invalid

### Requirement: Typed values

Each key SHALL take a value of the type its flag takes: `repositories` a list of strings;
`keep`, `max-attempts` and `max-deletions` integers; `max-deletion-share` a number;
`fail-on-skip` and `allow-hosted` booleans; `timeout` a string holding a duration such as
`30sec`; every other key that has a flag a string. `disabled`, which has no flag, SHALL be a
boolean. A value of the wrong type SHALL be a usage error naming the key and the file.

#### Scenario: Duration given as text

- **WHEN** a configuration file contains `timeout: 2min`
- **THEN** each request uses a two-minute timeout

#### Scenario: Wrong type refused

- **WHEN** a configuration file contains `keep: "three"` or `fail-on-skip: "yes"`
- **THEN** the run aborts with a usage error naming that key and the file

#### Scenario: Whole number accepted as a share

- **WHEN** a configuration file contains `max-deletion-share: 1`
- **THEN** the value is accepted as the share 1.0

#### Scenario: Reason text refused for disabled

- **WHEN** a configuration file contains `disabled: "until the migration is done"`
- **THEN** the run aborts with a usage error naming `disabled` and the file

## ADDED Requirements

### Requirement: A configuration file can disable its run

A configuration file containing `disabled: true` SHALL make the run send no request to Nexus,
enumerate and delete nothing, and exit 0, whatever flags are passed, the execute flag and a
repository selection included. `disabled: false` and an absent key SHALL change nothing. No flag
SHALL override the key. Standard error SHALL state that the file is disabled and nothing was
done.

#### Scenario: Disabled file in a dry run

- **WHEN** the tool is invoked with a configuration file containing `disabled: true` and valid settings
- **THEN** the exit code is 0 and no HTTP request is made
- **AND** standard error names the file and states that it is disabled and nothing was done

#### Scenario: Execute flag does not override

- **WHEN** the same file is run with the execute flag
- **THEN** no HTTP request is made, nothing is deleted and the exit code is 0

#### Scenario: Command-line selection does not override

- **WHEN** the same file is run with a repository named on the command line
- **THEN** no HTTP request is made and the exit code is 0

#### Scenario: Disabled false

- **WHEN** a configuration file contains `disabled: false`
- **THEN** the run behaves exactly as it would without the key

### Requirement: A disabled file is still validated

Every check that a run performs before its first request SHALL apply to a disabled file, to the
command line it is run with and to the environment it is run in, and a failure SHALL be the usage
error it would be without the key. A disabled file SHALL never hide a configuration fault that
would fail it once re-enabled.

#### Scenario: Misspelt key in a disabled file

- **WHEN** a configuration file contains `disabled: true` and `keeep: 3`
- **THEN** the run aborts with a usage error naming `keeep` and the file

#### Scenario: Refused key in a disabled file

- **WHEN** a configuration file contains `disabled: true` and `execute: false`
- **THEN** the run aborts with the usage error for the `execute` key

#### Scenario: Required cap still required

- **WHEN** a configuration file contains `disabled: true` and no deletion cap, and the switch that requires a cap is passed
- **THEN** the run aborts with the usage error for a missing cap

#### Scenario: Nexus URL still required

- **WHEN** a configuration file contains `disabled: true` and no `url`, and neither `NEXUS_URL` nor the URL flag is set
- **THEN** the run aborts with exit code 2 and the usage error for a missing Nexus URL

#### Scenario: Placeholder Nexus URL still refused

- **WHEN** a configuration file contains `disabled: true` and `NEXUS_URL` is `https://nexus.example.com`
- **THEN** the run aborts with exit code 2 and the placeholder refusal naming `NEXUS_URL`
