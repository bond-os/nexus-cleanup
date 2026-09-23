## Purpose

Defines the machine-parsable summary a cleanup run produces: one record per component
decision plus an aggregate block, encoded as JSON or CSV, stable enough that a later CI step
can render a human-readable report or diff two runs without re-deriving anything.

## ADDED Requirements

### Requirement: One record per component decision

The report SHALL contain exactly one record per component decision, and each record SHALL
carry at least the repository, format, scope, group/namespace, name, variant, version,
component identifier, decision, reason, rank within its ordered group, total asset size in
bytes, the newest asset timestamp, whether the component was actually deleted, and any
per-component error. Fields that do not apply SHALL be present and empty rather than omitted.

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

### Requirement: Decisions and reasons are a closed set

The decision field SHALL take one of exactly three values — kept, marked for deletion, or
skipped — and the reason field SHALL take a value from a documented, stable set of machine
readable codes. New codes MAY be added over time; existing codes SHALL NOT change meaning.

#### Scenario: Skipped group carries its cause

- **WHEN** a group was skipped because a version could not be parsed
- **THEN** every record of that group has the skipped decision and a reason code identifying an unorderable group

#### Scenario: Retained component carries its cause

- **WHEN** a component is kept because it is within the keep count
- **THEN** its record carries the reason code for being within the retention window

#### Scenario: Reason codes are machine readable

- **WHEN** a consumer groups the report by reason
- **THEN** the values are stable identifiers, not free-form human sentences

### Requirement: Aggregate summary

The report SHALL include an aggregate block covering the run mode, the start and end
timestamps, the Nexus base URL, the repositories processed, the keep count in effect, and
counts of components total, kept, marked for deletion, deleted, skipped and failed, together
with the reclaimable and actually reclaimed byte totals. Counts SHALL be internally
consistent with the records.

#### Scenario: Counts match the records

- **WHEN** a report is produced
- **THEN** the kept, deletion, skipped and failed counts sum to the total component count
- **AND** each count equals the number of distinct components with that decision in the records

#### Scenario: Dry run reports reclaimable but not reclaimed bytes

- **WHEN** a dry run finishes
- **THEN** the reclaimable byte total reflects the components marked for deletion
- **AND** the reclaimed byte total is zero

#### Scenario: Credentials absent from the summary

- **WHEN** the aggregate block records the Nexus base URL
- **THEN** no username, password or authorization header value appears anywhere in the report

### Requirement: JSON encoding is the default

With no format selected the tool SHALL write a single JSON document to standard output
containing the aggregate block and the array of records, valid as a whole and parseable by a
standard JSON reader without preprocessing.

#### Scenario: Default output parses as JSON

- **WHEN** the tool is invoked without a format flag and its standard output is captured
- **THEN** the captured text parses as a single JSON document containing both the summary and the records

#### Scenario: Empty run still emits a document

- **WHEN** a run produces no records at all
- **THEN** standard output still contains a valid JSON document with an empty record array and a zeroed summary

### Requirement: CSV encoding on request

When CSV is selected the tool SHALL write the records as a CSV table with a header row and
one row per record, with fields in a documented, stable order, and SHALL correctly quote
values containing separators, quotes or newlines. Because CSV carries no place for the
aggregate, the tool SHALL make the aggregate available separately on request.

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

### Requirement: Report is emitted even when the run fails

The tool SHALL emit whatever report it has whenever it has begun making decisions, including
runs that end with deletion failures or that were cut short, so the operator can always see
what was decided and what was actually done.

#### Scenario: Deletion failures still reported

- **WHEN** an executing run finishes with some deletions failing
- **THEN** the report is written to standard output as usual
- **AND** failed components carry their error text in the per-component error field

#### Scenario: Configuration error produces no report

- **WHEN** the run aborts on a configuration error before any component is enumerated
- **THEN** no report document is written to standard output
- **AND** the cause is written to standard error

### Requirement: Report renders to a human-readable summary

The report SHALL be sufficient on its own to render an operator-facing summary — what would
be or was deleted, per repository and per group, how much space it frees, and what was
skipped and why — without any further call to Nexus.

#### Scenario: Rendering from the report alone

- **WHEN** a consumer is given only the report document
- **THEN** it can produce a per-repository breakdown of kept, deleted and skipped counts with byte totals and skip reasons
