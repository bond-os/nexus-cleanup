# config-file Specification

## Purpose

Lets a run take its settings from a YAML file instead of flags, so that one generic pipeline can
be pointed at several reviewed configuration files, each describing one run against its own
repositories with its own settings.

## Requirements

### Requirement: Configuration file option

The tool SHALL accept a configuration file option naming a YAML document whose top level is a
mapping. Each key SHALL name a setting by its command-line flag name, spelled exactly as the
flag without its leading dashes. One file SHALL describe exactly one run.

#### Scenario: Settings read from a file

- **WHEN** the tool is invoked with a configuration file containing `keep: 3` and `repositories: [yum-proxy-a]`
- **THEN** the run processes `yum-proxy-a` with a keep count of 3

#### Scenario: Keys spelled as flags

- **WHEN** a configuration file contains `max-deletions: 200` and `from-path: '^/(?P<name>app)/(?P<version>[0-9]{8})/'`
- **THEN** the run applies a deletion cap of 200 and that path pattern, exactly as if the flags had been passed

#### Scenario: No file given

- **WHEN** the tool is invoked without the configuration file option
- **THEN** no file is read and behaviour is identical to that of a tool without the option

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

### Requirement: Execution is never a file setting

A configuration file SHALL NOT be able to make a run delete anything. An `execute` key SHALL be
refused with a usage error stating that deletion is requested only by the execute flag, and no
other key or value in the file SHALL imply execution.

#### Scenario: Execute key refused

- **WHEN** a configuration file contains `execute: true`
- **THEN** the run aborts with a usage error naming `execute` and directing the operator to the execute flag
- **AND** nothing is enumerated or deleted

#### Scenario: Execute key refused even when false

- **WHEN** a configuration file contains `execute: false`
- **THEN** the run aborts with the same usage error

#### Scenario: File-configured run is a dry run

- **WHEN** the tool is invoked with a configuration file and without the execute flag
- **THEN** the run is a dry run whatever the file contains

### Requirement: Credentials are never a file setting

A configuration file SHALL NOT carry a password. A `password` key, or a `url` value carrying
user information, SHALL be refused with a usage error that names the key and the environment
variable to use instead, and SHALL NOT include the offending value in any message.

#### Scenario: Password key refused

- **WHEN** a configuration file contains `password: s3cret`
- **THEN** the run aborts with a usage error naming `password` and `NEXUS_PASSWORD`
- **AND** the text `s3cret` appears in no output

#### Scenario: Credentials embedded in the URL refused

- **WHEN** a configuration file contains `url: https://bot:s3cret@nexus.example.com`
- **THEN** the run aborts with a usage error naming `url`
- **AND** the text `s3cret` appears in no output

#### Scenario: Username allowed

- **WHEN** a configuration file contains `username: cleanup-bot` and the password comes from `NEXUS_PASSWORD`
- **THEN** requests authenticate as `cleanup-bot`

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

### Requirement: File values are validated like flags

A value read from the file SHALL be subject to every validation the equivalent flag is subject
to, and a failure SHALL name the key and the file.

#### Scenario: Invalid keep count in the file

- **WHEN** a configuration file contains `keep: 0`
- **THEN** the run aborts with a usage error naming `keep` and the file

#### Scenario: Path pattern without its groups in the file

- **WHEN** a configuration file contains a `from-path` value lacking a `version` group
- **THEN** the run aborts with a usage error naming `from-path` and the file
- **AND** no repository is enumerated

### Requirement: Unusable file refused

A configuration file that does not exist, cannot be read, does not parse as YAML, or whose top
level is not a mapping SHALL be refused with a usage error naming the file, before any request
is made. An empty document SHALL be treated as a mapping with no keys.

#### Scenario: Missing file

- **WHEN** the configuration file option names a path that does not exist
- **THEN** the run aborts with a usage error naming that path

#### Scenario: Top level is a list

- **WHEN** the file's top level is a YAML sequence
- **THEN** the run aborts with a usage error stating that the file must contain a mapping

#### Scenario: Empty file

- **WHEN** the file is empty and the repository selection is given on the command line
- **THEN** the run proceeds with every other setting at its default

### Requirement: Layering of file, environment and flags

A flag SHALL override the file. For the URL and username the environment SHALL override the
file and a flag SHALL override the environment. For every other setting the file SHALL override
the default. A boolean switch SHALL be in effect when either the flag or the file sets it.

#### Scenario: Flag overrides the file

- **WHEN** the file contains `keep: 3` and `--keep 5` is passed
- **THEN** the keep count is 5

#### Scenario: Environment overrides the file's URL

- **WHEN** the file contains `url: https://a.example.com`, `NEXUS_URL` is `https://b.example.com`, and no URL flag is passed
- **THEN** requests go to `https://b.example.com`

#### Scenario: File overrides the default

- **WHEN** the file contains `format: csv` and no format flag is passed
- **THEN** the report is written as CSV

#### Scenario: Switch set in the file

- **WHEN** the file contains `fail-on-skip: true` and the flag is not passed
- **THEN** skipped groups make the run exit non-zero

### Requirement: Repository selection replaced as a whole

A repository selection on the command line — repository names, a pattern, or both — SHALL
replace the file's `repositories` and `pattern` together. When the command line selects nothing,
the file's selection SHALL apply.

#### Scenario: Names on the command line replace a file pattern

- **WHEN** the file contains `pattern: "yum-*"` and the command line names `npm-proxy`
- **THEN** only `npm-proxy` is processed

#### Scenario: Selection from the file

- **WHEN** the file contains `repositories: [a, b]` and the command line names no repository and no pattern
- **THEN** exactly `a` and `b` are processed

#### Scenario: No selection anywhere

- **WHEN** neither the file nor the command line selects a repository
- **THEN** the run aborts with the usage error for a missing selection

### Requirement: Relative paths resolve against the working directory

A path value in the file, such as `summary-out`, SHALL resolve against the working directory of
the run, exactly as the equivalent flag does, and not against the file's own directory.

#### Scenario: Summary path in a nested file

- **WHEN** the run's working directory is `/work`, the file is `configs/yum.yaml` and it contains `summary-out: summary.json`
- **THEN** the aggregate is written to `/work/summary.json`

### Requirement: Published configuration schema

Each release SHALL carry a JSON Schema describing the configuration file at the fixed path
`schema/config.schema.json` in the repository at that release's tag. The schema SHALL list
exactly the recognised keys with their types, SHALL forbid every other key, and SHALL describe
why a refused key is refused.

#### Scenario: Schema reachable at a pinned version

- **WHEN** a release `vX.Y.Z` exists
- **THEN** `schema/config.schema.json` at tag `vX.Y.Z` describes the configuration file accepted by the tool at version `X.Y.Z`

#### Scenario: Unknown key invalid against the schema

- **WHEN** a configuration file containing `keeep: 3` is validated against the schema
- **THEN** validation fails on `keeep`

#### Scenario: Refused key explained by the schema

- **WHEN** a configuration file containing `execute: true` or `password: x` is validated against the schema
- **THEN** validation fails on that key
- **AND** the schema's description of that key states why it is refused and what to use instead

### Requirement: Schema agrees with the tool

Every configuration file the tool accepts SHALL be valid against the schema of the same
version. Where the schema cannot express a rule exactly, it SHALL be more permissive than the
tool rather than stricter, and the tool SHALL remain the authority on what is accepted.

#### Scenario: Accepted file is valid

- **WHEN** a configuration file is accepted by the tool
- **THEN** it is valid against the schema of the same version

#### Scenario: Wrong type invalid against the schema

- **WHEN** a configuration file containing `keep: "three"` is validated against the schema
- **THEN** validation fails on `keep`

#### Scenario: Rule the schema only approximates

- **WHEN** a configuration file's `from-path` names both groups but does not compile
- **THEN** the file may be valid against the schema
- **AND** the tool still refuses it with a usage error
