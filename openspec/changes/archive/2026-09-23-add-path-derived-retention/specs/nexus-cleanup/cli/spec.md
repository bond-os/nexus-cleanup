## ADDED Requirements

### Requirement: Path pattern option

The tool SHALL accept a path pattern that assigns the grouping name and the version of each
component it matches, and SHALL accept `date` among the selectable version schemes. The pattern
SHALL contain both a `name` and a `version` named group and SHALL compile; otherwise the run
SHALL be refused before any repository is enumerated. The path pattern SHALL be combinable with
the scope pattern, the version scheme and every other option.

#### Scenario: Valid pattern accepted

- **WHEN** the operator supplies a pattern with `name` and `version` groups
- **THEN** the run proceeds and applies it to every targeted repository

#### Scenario: Pattern missing a required group refused

- **WHEN** the supplied pattern lacks the `name` group or the `version` group
- **THEN** the run aborts with a usage error naming the path pattern option
- **AND** no repository is enumerated

#### Scenario: Uncompilable pattern refused

- **WHEN** the supplied pattern is not a valid expression
- **THEN** the run aborts with a usage error naming the path pattern option

#### Scenario: Date scheme selectable

- **WHEN** the operator selects the `date` version scheme
- **THEN** the selection is accepted and applied to every targeted repository
