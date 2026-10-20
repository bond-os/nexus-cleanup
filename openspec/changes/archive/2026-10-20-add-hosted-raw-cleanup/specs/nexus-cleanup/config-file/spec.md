## MODIFIED Requirements

### Requirement: Recognised keys

The file SHALL accept exactly these keys: `url`, `username`, `repositories`, `pattern`, `keep`,
`timeout`, `max-attempts`, `format`, `version-scheme`, `scope-from-path`, `from-path`,
`fail-on-skip`, `max-deletions`, `max-deletion-share`, `summary-out` and `allow-hosted`, plus a
`$schema` key, which SHALL be a string and SHALL otherwise be ignored. Any other key SHALL be
refused with a usage error naming the key and the file, before any request is made.

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

### Requirement: Typed values

Each key SHALL take a value of the type its flag takes: `repositories` a list of strings;
`keep`, `max-attempts` and `max-deletions` integers; `max-deletion-share` a number;
`fail-on-skip` and `allow-hosted` booleans; `timeout` a string holding a duration such as
`30sec`; every other key a string. A value of the wrong type SHALL be a usage error naming the
key and the file.

#### Scenario: Duration given as text

- **WHEN** a configuration file contains `timeout: 2min`
- **THEN** each request uses a two-minute timeout

#### Scenario: Wrong type refused

- **WHEN** a configuration file contains `keep: "three"` or `fail-on-skip: "yes"`
- **THEN** the run aborts with a usage error naming that key and the file

#### Scenario: Whole number accepted as a share

- **WHEN** a configuration file contains `max-deletion-share: 1`
- **THEN** the value is accepted as the share 1.0
