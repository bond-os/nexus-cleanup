# cli Specification

## Purpose

Defines the command-line surface of the cleanup tool as CI operators use it: how the target
repositories, keep count and output format are selected, how environment variables and flags
combine, why nothing is ever deleted unless deletion is asked for explicitly, and what the
process exit code tells the pipeline.

## Requirements

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

#### Scenario: Execute is not implied by a configuration file

- **WHEN** the tool is invoked with a configuration file and without the execute flag
- **THEN** the run remains a dry run whatever the file contains

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

### Requirement: Configuration precedence and validation

The tool SHALL read connection settings from the environment and SHALL let an equivalent
command-line flag override the environment value for the same setting. When a configuration
file is given, its values SHALL sit below both: a flag overrides the file for every setting, and
the environment overrides the file for connection settings. All configuration, from every
source, SHALL be validated before any repository is enumerated, and an invalid value SHALL abort
the run with a message naming the offending setting.

#### Scenario: Flag overrides environment

- **WHEN** `NEXUS_URL` is set in the environment and a URL flag with a different value is passed
- **THEN** the flag's value is used

#### Scenario: Invalid value rejected up front

- **WHEN** a keep count, timeout or retry limit is not a valid positive value
- **THEN** the run aborts with a usage error naming that setting
- **AND** no repository is enumerated

#### Scenario: Flag overrides the configuration file

- **WHEN** a configuration file sets a keep count and a different keep count is passed as a flag
- **THEN** the flag's value is used

#### Scenario: Invalid file value rejected up front

- **WHEN** a configuration file holds an invalid value for any setting
- **THEN** the run aborts with a usage error naming that setting and the file
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

### Requirement: Version flag

The tool SHALL accept a version flag that writes the tool's version, and nothing else, to
standard output and exits successfully. The flag SHALL take effect without any connection
setting or repository selection, SHALL NOT validate other configuration and SHALL NOT contact
Nexus.

#### Scenario: Version printed without configuration

- **WHEN** the tool is invoked with only the version flag and no `NEXUS_URL`, credentials or repository selection
- **THEN** standard output contains the version string followed by a newline, such as `0.1.0`
- **AND** the exit code is 0
- **AND** no HTTP request is made

#### Scenario: Version flag with other flags

- **WHEN** the version flag is passed together with other flags, including the execute flag
- **THEN** only the version is printed and the tool exits with code 0
- **AND** no repository is enumerated and nothing is deleted

### Requirement: A deletion cap can be required

The tool SHALL accept a switch that requires a deletion cap. With it, a run — dry or executing —
whose resolved configuration sets neither an absolute nor a proportional cap SHALL be refused
with a usage error naming both cap settings, before any repository is enumerated. The switch
SHALL NOT imply execution and SHALL NOT be settable from a configuration file.

#### Scenario: Cap missing

- **WHEN** the tool is invoked with the require-cap switch and no cap is set by flag or file
- **THEN** the run aborts with a usage error naming the absolute and the proportional cap settings
- **AND** no repository is enumerated

#### Scenario: Cap from the configuration file

- **WHEN** the tool is invoked with the require-cap switch and a configuration file setting `max-deletions: 200`
- **THEN** the run proceeds with a cap of 200

#### Scenario: Dry run also checked

- **WHEN** the tool is invoked with the require-cap switch, without the execute flag, and no cap is set
- **THEN** the run aborts with the same usage error, so a missing cap surfaces in the dry run rather than at execution

#### Scenario: Not a file setting

- **WHEN** a configuration file contains `require-cap: true`
- **THEN** the run aborts with a usage error naming `require-cap` as an unknown key

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

### Requirement: Init subcommand

The tool SHALL accept `init` as its first argument to select the repository initialisation
subcommand instead of a cleanup run. The subcommand SHALL take effect without any connection
setting or repository selection and SHALL NOT validate cleanup configuration. A repository
named `init` SHALL remain selectable through a pattern or a configuration file.

#### Scenario: Subcommand instead of a run

- **WHEN** the tool is invoked as `init --ci gitlab`
- **THEN** it initialises a configuration repository and performs no cleanup run
- **AND** the absence of `NEXUS_URL` and of a repository selection is not an error

#### Scenario: Run flags are not accepted by init

- **WHEN** the tool is invoked as `init --ci gitlab --execute`
- **THEN** the exit code is the usage error code and no file is written

#### Scenario: Repository named init

- **WHEN** a proxy repository is named `init` and the operator selects it with `--pattern init`
- **THEN** that repository is processed by a cleanup run

### Requirement: Nexus URL must parse as http or https

After the Nexus URL is resolved from any source, the tool SHALL refuse it with a usage error when
it cannot be parsed as a URL with a host, or when its scheme is neither `http` nor `https`. The
error SHALL name the source of the value, quote the value, and be raised before any request is
made.

#### Scenario: Unparseable URL from the environment

- **WHEN** `NEXUS_URL` is `http//nexus` and no URL flag is passed
- **THEN** the run aborts with exit code 2
- **AND** the message names `NEXUS_URL` and quotes `http//nexus`
- **AND** no HTTP request is made

#### Scenario: URL without a host

- **WHEN** the URL flag is `https://`
- **THEN** the run aborts with exit code 2 and the message names `--url`

#### Scenario: Unparseable URL from a configuration file

- **WHEN** the configuration file `configs/a.yaml` contains `url: http//nexus` and neither the flag nor `NEXUS_URL` is set
- **THEN** the run aborts with exit code 2 and the message names `'url' in configs/a.yaml`

#### Scenario: Scheme other than http or https

- **WHEN** the URL is `httpx://nexus.test` or `ftp://nexus.test`
- **THEN** the run aborts with exit code 2 and the message states that the URL must be an http or https URL

#### Scenario: Ordinary URLs accepted

- **WHEN** the URL is `https://nexus.test`, `http://nexus.test:8081/`, `https://nexus.test/nexus` or `http://[::1]:8081`
- **THEN** the URL is accepted

#### Scenario: Parse failure precedes other validation

- **WHEN** the URL cannot be parsed and the keep count is also invalid
- **THEN** the run aborts with exit code 2 and the message is the URL refusal

### Requirement: Placeholder Nexus URL refused

After the Nexus URL is resolved from any source, the tool SHALL refuse it with a usage error when
its host is `example`, `example.com`, `example.net`, `example.org` or `invalid`, or a name under
one of them, compared without regard to case or a trailing dot. The error SHALL name the source
of the value, state that the address is a placeholder, and be raised before any request is made.

#### Scenario: Placeholder from the environment

- **WHEN** `NEXUS_URL` is `https://nexus.example.com` and no URL flag is passed
- **THEN** the run aborts with exit code 2
- **AND** the message names `NEXUS_URL` and states that `https://nexus.example.com` is a placeholder to be replaced by the address of the operator's Nexus
- **AND** no HTTP request is made

#### Scenario: Placeholder from a flag

- **WHEN** the URL flag is `https://example.org`
- **THEN** the run aborts with exit code 2 and the message names `--url`

#### Scenario: Placeholder from a configuration file

- **WHEN** the configuration file `configs/a.yaml` contains `url: https://nexus.example.net` and neither the flag nor `NEXUS_URL` is set
- **THEN** the run aborts with exit code 2 and the message names `'url' in configs/a.yaml`

#### Scenario: Every reserved name refused

- **WHEN** the URL's host is `example`, `nexus.example`, `example.com`, `a.b.example.com`, `example.net`, `example.org`, `invalid` or `nexus.example.invalid`, in any letter case, with or without a port or a trailing dot
- **THEN** the run aborts with exit code 2

#### Scenario: Look-alike names accepted

- **WHEN** the URL's host is `example.company.com`, `myexample.com` or `nexus.examples.org`
- **THEN** the URL is accepted

#### Scenario: Local development names accepted

- **WHEN** the URL's host is `localhost`, `nexus.localhost`, `nexus.test`, `127.0.0.1` or `[::1]`
- **THEN** the URL is accepted

#### Scenario: Refusal precedes other validation

- **WHEN** the URL is a placeholder and the keep count is also invalid
- **THEN** the run aborts with exit code 2 and the message is the placeholder refusal

#### Scenario: Init and the version flag unaffected

- **WHEN** `NEXUS_URL` is `https://nexus.example.com` and the tool is invoked with the version flag or as `init --ci gitlab`
- **THEN** the exit code is 0
