## MODIFIED Requirements

### Requirement: One record per component decision

The report SHALL contain exactly one record per component decision, and each record SHALL
carry at least the repository, format, scope, group/namespace, name, variant, version,
component identifier, decision, reason, rank within its ordered group, total asset size in
bytes, the newest asset timestamp, whether the component was actually deleted, any
per-component error, and the component's asset path. Fields that do not apply SHALL be present and empty rather than omitted.

#### Scenario: Record content

- **WHEN** a component is marked for deletion in a dry run
- **THEN** its record shows the decision as a deletion, a reason, its rank in the ordered group, and a deleted flag that is false

#### Scenario: Fields are always present

- **WHEN** a component has no group/namespace and no error
- **THEN** those fields are present in the record with empty values

#### Scenario: Multi-variant component reported once per group

- **WHEN** a component belongs to two variant groups
- **THEN** the report contains one record per group membership, each naming its variant
- **AND** the aggregate counts that component once

#### Scenario: Path-derived record still identifies its file

- **WHEN** a component is grouped by a path pattern that extracts the name `some_dir`
- **THEN** its record's name is `some_dir` and its path is the file's own asset path, such as `/some_dir/20250101/app.tar.gz`

#### Scenario: Outside-pattern component reported

- **WHEN** a path pattern is supplied and a component does not match it
- **THEN** the component has a record with a kept decision and the outside-pattern reason

### Requirement: CSV encoding on request

When CSV is selected the tool SHALL write the records as a CSV table with a header row and
one row per record, with fields in a documented, stable order, and SHALL correctly quote
values containing separators, quotes or newlines. Because CSV carries no place for the
aggregate, the tool SHALL make the aggregate available separately on request. A field added to
the record SHALL be appended after the existing columns, so that consumers addressing columns by
position are unaffected.

#### Scenario: CSV table shape

- **WHEN** CSV output is selected
- **THEN** standard output begins with a header row naming every record field
- **AND** each subsequent row corresponds to exactly one record

#### Scenario: Values needing quoting

- **WHEN** a field value contains a comma, a double quote or a newline
- **THEN** the emitted value is quoted and escaped so that a standard CSV reader recovers the original value

#### Scenario: Aggregate alongside CSV

- **WHEN** CSV output is selected and the operator asks for the aggregate to be written to a path
- **THEN** the aggregate block is written to that path as JSON
- **AND** standard output still contains only the CSV table

#### Scenario: New fields appended

- **WHEN** the record gains a field
- **THEN** the new column appears after every pre-existing column
- **AND** every pre-existing column keeps its position
