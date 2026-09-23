## Purpose

Defines the command-line surface of the cleanup tool as CI operators use it: how the target
repositories, keep count and output format are selected, how environment variables and flags
combine, why nothing is ever deleted unless deletion is asked for explicitly, and what the
process exit code tells the pipeline.

## ADDED Requirements

### Requirement: Dry run is the default

The tool SHALL run in dry-run mode unless the operator passes an explicit execute flag. In
dry-run mode the tool SHALL perform every read, grouping and ordering step and produce the
full report, and SHALL issue no deletion request of any kind.

#### Scenario: No execute flag given

- **WHEN** the tool is invoked without the execute flag
- **THEN** the report lists the components that would be deleted
- **AND** no deletion request is sent to Nexus
- **AND** the report identifies the run mode as a dry run

#### Scenario: Execute flag given

- **WHEN** the tool is invoked with the execute flag
- **THEN** each component marked for deletion is deleted
- **AND** the report identifies the run mode as an executing run

#### Scenario: Execute flag is not implied

- **WHEN** any other flag or environment variable is set, including verbose or format flags
- **THEN** the run remains a dry run unless the execute flag itself was passed

### Requirement: Repository targeting

The tool SHALL accept one or more repository names and/or a name pattern, and SHALL operate
only on repositories that both match the selection and are proxy repositories. Invoking the
tool with no selection SHALL be refused rather than interpreted as "every repository".

#### Scenario: Explicit repository names

- **WHEN** the operator names two proxy repositories
- **THEN** exactly those two repositories are processed

#### Scenario: Pattern selection

- **WHEN** the operator supplies a name pattern
- **THEN** every proxy repository whose name matches the pattern is processed
- **AND** matching repositories that are not proxies are excluded and reported as excluded

#### Scenario: No selection supplied

- **WHEN** the tool is invoked with neither a repository name nor a pattern
- **THEN** the tool exits with a usage error without contacting Nexus

#### Scenario: Pattern matches nothing

- **WHEN** the supplied pattern matches no proxy repository
- **THEN** the tool emits an empty report and a diagnostic saying the selection matched nothing
- **AND** the exit code indicates success

### Requirement: Configuration precedence and validation

The tool SHALL read connection settings from the environment and SHALL let an equivalent
command-line flag override the environment value for the same setting. All configuration
SHALL be validated before any repository is enumerated, and an invalid value SHALL abort the
run with a message naming the offending setting.

#### Scenario: Flag overrides environment

- **WHEN** `NEXUS_URL` is set in the environment and a URL flag with a different value is passed
- **THEN** the flag's value is used

#### Scenario: Invalid value rejected up front

- **WHEN** a keep count, timeout or retry limit is not a valid positive value
- **THEN** the run aborts with a usage error naming that setting
- **AND** no repository is enumerated

### Requirement: Scope pattern override

The tool SHALL accept a pattern that names the scope within an asset path and SHALL apply it
to every targeted repository in place of the per-format default. An invalid pattern SHALL be
refused before any repository is enumerated.

#### Scenario: Pattern applied across formats

- **WHEN** the operator supplies a scope pattern
- **THEN** every targeted repository derives its scope from that pattern rather than its format default

#### Scenario: Invalid pattern refused up front

- **WHEN** the supplied scope pattern is not a valid expression, or names no scope
- **THEN** the run aborts with a usage error naming the pattern
- **AND** no repository is enumerated

### Requirement: Non-interactive operation

The tool SHALL never prompt for input, never require a terminal, and SHALL run to completion
under a CI runner with no controlling TTY. Progress and diagnostics SHALL be written to
standard error so that standard output carries only the report.

#### Scenario: Runs without a TTY

- **WHEN** the tool is invoked with standard output redirected to a file and no TTY attached
- **THEN** the run completes without prompting
- **AND** the file contains only the report

#### Scenario: Diagnostics separated from the report

- **WHEN** the tool emits progress or warning messages
- **THEN** those messages appear on standard error, not interleaved into the report on standard output

### Requirement: Exit codes

The tool SHALL signal its outcome through distinct process exit codes: success, per-component
deletion failures, usage or configuration error, unrecoverable API failure, and — only when
the operator asked for it — the presence of skipped groups.

#### Scenario: Successful run

- **WHEN** a run completes and every intended action succeeded
- **THEN** the exit code is 0

#### Scenario: Some deletions failed

- **WHEN** an executing run deletes some components but at least one deletion fails
- **THEN** the exit code is 1
- **AND** the report still contains a record for every component processed

#### Scenario: Usage or configuration error

- **WHEN** a required setting is missing or a supplied value is invalid
- **THEN** the exit code is 2

#### Scenario: Nexus unreachable or authentication rejected

- **WHEN** repository or component enumeration cannot be completed against Nexus
- **THEN** the exit code is 3
- **AND** no deletion is attempted

#### Scenario: Skipped groups made fatal on request

- **WHEN** the operator passes the flag that makes skipped groups fatal and at least one group was skipped
- **THEN** the exit code is 4

#### Scenario: Skipped groups tolerated by default

- **WHEN** groups are skipped and the operator did not pass that flag
- **THEN** the skipped groups appear in the report
- **AND** they do not by themselves change the exit code

### Requirement: Reusable module and thin entrypoint

The tool SHALL be published as an importable Nushell module whose commands are callable from
another script, plus an executable entrypoint script that only parses arguments, calls the
module and sets the exit code. Importing the module SHALL have no side effects: it SHALL not
contact Nexus, read credentials or write output.

#### Scenario: Module used programmatically

- **WHEN** another Nushell script imports the module and calls the planning command directly
- **THEN** it receives the decision records as structured Nushell data rather than encoded text

#### Scenario: Import is inert

- **WHEN** the module is imported
- **THEN** no HTTP request is made and nothing is written to standard output or standard error

### Requirement: Runs in a plain Nushell container

The tool SHALL run on a supported Nushell version inside an official Nushell container image
using only the Nushell standard library and built-in HTTP support, with no additional runtime
package, interpreter or external binary required.

#### Scenario: No external dependency invoked

- **WHEN** the tool executes a complete run in a container that contains only Nushell and its standard library
- **THEN** the run completes without invoking any external command

### Requirement: Deletion cap circuit breaker

The tool SHALL support a cap on how much a single executing run may delete, expressed as an
absolute component count and/or as a share of the components enumerated. When a run's
deletion plan exceeds the cap, the tool SHALL abort before deleting anything, emit the full
plan as a report, and exit with a distinct non-zero code, so that an unexpected mass
deletion — caused by a misconfigured pattern, an upstream renaming or a comparator change —
is surfaced instead of executed.

#### Scenario: Plan exceeds the absolute cap

- **WHEN** an executing run with a cap of 100 components plans to delete 250
- **THEN** no deletion is performed
- **AND** the report shows all 250 as marked for deletion with none deleted
- **AND** the exit code signals that the cap was exceeded

#### Scenario: Plan exceeds the proportional cap

- **WHEN** an executing run capped at half of the enumerated components plans to delete more than half
- **THEN** the run aborts before deleting anything and signals the cap

#### Scenario: Plan within the cap

- **WHEN** the deletion plan is at or below every configured cap
- **THEN** the deletions proceed as normal

#### Scenario: Cap does not affect a dry run

- **WHEN** a dry run's plan exceeds the cap
- **THEN** the report is produced in full
- **AND** the run is not treated as a failure
