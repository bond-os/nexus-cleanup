## MODIFIED Requirements

### Requirement: Aggregate summary

The report SHALL include an aggregate block covering the run mode, the start and end
timestamps, the Nexus base URL, the repositories processed, the keep count in effect, and
counts of components total, kept, marked for deletion, deleted, skipped and failed, together
with the reclaimable and actually reclaimed byte totals, and the version of the tool that
produced the report. Counts SHALL be internally consistent with the records. Fields added to
the aggregate SHALL be appended after the existing ones.

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

#### Scenario: Report names the tool version

- **WHEN** a report is produced by the tool at version 0.2.0
- **THEN** the aggregate block's tool version is `0.2.0`, equal to what the version flag prints
- **AND** the tool version is the last field of the aggregate block

#### Scenario: Records and CSV columns unaffected

- **WHEN** CSV output is selected
- **THEN** the record columns are exactly those produced before the tool version was added, in the same order
