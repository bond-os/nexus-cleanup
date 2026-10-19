## MODIFIED Requirements

### Requirement: Repository targeting

The tool SHALL accept one or more repository names and/or a name pattern, and SHALL operate
only on repositories that both match the selection and are eligible for cleanup. A pattern
SHALL select only proxy repositories; a raw hosted repository SHALL be selectable only by name,
and only when hosted repositories are allowed. Invoking the tool with no selection SHALL be
refused rather than interpreted as "every repository".

#### Scenario: Explicit repository names

- **WHEN** the operator names two proxy repositories
- **THEN** exactly those two repositories are processed

#### Scenario: Pattern selection

- **WHEN** the operator supplies a name pattern
- **THEN** every proxy repository whose name matches the pattern is processed
- **AND** matching repositories that are not proxies are excluded and reported as excluded

#### Scenario: Pattern excludes hosted repositories even when allowed

- **WHEN** the operator allows hosted repositories and supplies a pattern matching a raw hosted repository
- **THEN** that repository is excluded and reported as excluded, with a diagnostic stating that hosted repositories are selected only by name

#### Scenario: Named raw hosted repository

- **WHEN** the operator allows hosted repositories and names a raw hosted repository
- **THEN** that repository is processed

#### Scenario: No selection supplied

- **WHEN** the tool is invoked with neither a repository name nor a pattern
- **THEN** the tool exits with a usage error without contacting Nexus

#### Scenario: Pattern matches nothing

- **WHEN** the supplied pattern matches no proxy repository
- **THEN** the tool emits an empty report and a diagnostic saying the selection matched nothing
- **AND** the exit code indicates success

## ADDED Requirements

### Requirement: Hosted repository opt-in

The tool SHALL accept a switch that allows raw hosted repositories to be named for cleanup. The
switch SHALL be off by default, SHALL admit no repository by itself, and SHALL NOT imply
execution: a run with it remains a dry run unless the execute flag is passed.

#### Scenario: Switch off by default

- **WHEN** the operator names a raw hosted repository without the switch
- **THEN** the repository is refused with a message naming the switch
- **AND** nothing is enumerated or deleted in it

#### Scenario: Switch does not imply execution

- **WHEN** the operator passes the switch and names a raw hosted repository, without the execute flag
- **THEN** the run is a dry run and no deletion request is sent

#### Scenario: Switch alone selects nothing

- **WHEN** the operator passes the switch with a pattern and names no repository
- **THEN** the selection is that of the pattern alone, which contains no hosted repository

### Requirement: Raw hosted repository without a path pattern is reported

When a raw hosted repository is processed without a path pattern, the tool SHALL proceed and
SHALL write a diagnostic to standard error, naming the repository, stating that nothing in it
can be deleted without a path pattern. The diagnostic SHALL NOT change the report or the exit
code.

#### Scenario: Diagnostic without a path pattern

- **WHEN** the operator allows hosted repositories, names a raw hosted repository and supplies no path pattern
- **THEN** standard error carries a diagnostic naming that repository and the path pattern option
- **AND** every component of it is kept
- **AND** the exit code is that of a run with nothing to delete

#### Scenario: No diagnostic with a path pattern

- **WHEN** the same run supplies a path pattern
- **THEN** no such diagnostic is written
