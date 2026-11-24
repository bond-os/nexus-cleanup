# Spec Delta

## MODIFIED Requirements

### Requirement: Upgrade is local and contained

`upgrade` SHALL work in the working directory unless another is given, SHALL read and write no
file other than those whose pins it moves, and SHALL need no environment variable or credential
and make no network request. It SHALL reject a symlink at any candidate path or in any parent
directory below the target directory before reading file content or writing a change. The command
SHALL list each file it changed and exit 0 whether or not anything changed. An unknown option, an
unsafe symlink path or an unusable directory SHALL be a usage error.

#### Scenario: Other files untouched

- **WHEN** the repository holds files `init` does not write, outside `configs/`
- **THEN** `upgrade` neither reads nor changes them

#### Scenario: Nothing to upgrade

- **WHEN** every pin already names the running version
- **THEN** no file is written, the command says nothing was changed, and the exit code is 0

#### Scenario: Unknown option

- **WHEN** `upgrade --execute` is run
- **THEN** the exit code is the usage error code and no file is written

#### Scenario: Candidate file is a symlink

- **WHEN** an `upgrade` candidate path is a symlink to a file outside the configuration repository
- **THEN** the command fails with a usage error naming the candidate path
- **AND** the symlink target is unchanged
- **AND** no candidate file is read or changed

#### Scenario: Candidate parent is a symlink

- **WHEN** a parent directory below the target directory is a symlink
- **THEN** `upgrade` fails before reading or writing through that directory
- **AND** no other candidate is changed

#### Scenario: Check refuses a symlink

- **WHEN** `upgrade --check` finds a candidate path or parent directory that is a symlink
- **THEN** the command fails with a usage error and writes nothing
- **AND** the symlink target is unchanged

#### Scenario: Stale-pin scan does not follow symlinks

- **WHEN** `init` checks for stale pins in a repository containing a symlinked `upgrade` candidate
- **THEN** the stale-pin scan does not read the symlink target
- **AND** it does not report the symlinked candidate as stale
