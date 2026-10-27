# Spec Delta

## MODIFIED Requirements

### Requirement: Aggregate summary

The report SHALL include an aggregate block covering the run mode, the start and end
timestamps, the Nexus base URL, the repositories processed, the keep count in effect, and
counts of components total, kept, marked for deletion, deleted, skipped and failed, together
with the reclaimable and actually reclaimed byte totals, the version of the tool that
produced the report, the configuration file the run was given, and whether that file disabled
the run. Counts SHALL be internally consistent with the records. Fields added to the aggregate
SHALL be appended after the existing ones.

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
- **AND** the tool version immediately follows the reclaimed byte total

#### Scenario: Report names the configuration file

- **WHEN** a run is given the configuration file `configs/yum.yaml`
- **THEN** the aggregate block's configuration file field is `configs/yum.yaml`, exactly as passed
- **AND** that field immediately follows the tool version

#### Scenario: No configuration file

- **WHEN** a run is given no configuration file
- **THEN** the configuration file field is present and empty

#### Scenario: Report records a disabled run

- **WHEN** a run is given a configuration file containing `disabled: true`
- **THEN** the aggregate block's disabled field is `true`
- **AND** that field is the last field of the aggregate block, after the configuration file

#### Scenario: Enabled run

- **WHEN** a run is given no configuration file, or one without `disabled: true`
- **THEN** the disabled field is present and `false`

#### Scenario: Records and CSV columns unaffected

- **WHEN** CSV output is selected
- **THEN** the record columns are exactly those produced before the tool version was added, in the same order

## ADDED Requirements

### Requirement: A disabled run still emits its report

A run disabled by its configuration file SHALL emit the report of a run that processed nothing,
in the selected format, and SHALL write the aggregate to the requested path when one is given,
so that every file a pipeline runs leaves a report and a disabled one says so.

#### Scenario: JSON report of a disabled run

- **WHEN** a disabled file is run with JSON output
- **THEN** standard output is a valid JSON document with an empty record array, zero counts and the disabled field `true`

#### Scenario: CSV report of a disabled run

- **WHEN** a disabled file selects CSV output
- **THEN** standard output is the CSV header row and nothing else

#### Scenario: Aggregate written for a disabled run

- **WHEN** a disabled file is run with a path for the aggregate
- **THEN** the aggregate is written to that path with the disabled field `true` and an empty repository list
