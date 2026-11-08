# Spec Delta

## ADDED Requirements

### Requirement: Keep existing files on request

`init` SHALL accept a skip-existing option. With it, `init` SHALL write the planned files that do not exist, leave every planned file that exists unchanged, and list each kept path on standard error. The exit code SHALL be 0 whether or not anything was written. Giving it together with the force option SHALL be a usage error, with nothing written.

#### Scenario: New files added to an existing repository

- **WHEN** `init --ci gitlab --editor intellij --skip-existing` is run in a repository holding an edited `.gitlab-ci.yml` and no `.idea/jsonSchemas.xml`
- **THEN** `.idea/jsonSchemas.xml` is written and listed
- **AND** `.gitlab-ci.yml` is unchanged and listed as kept
- **AND** the exit code is 0

#### Scenario: Nothing missing

- **WHEN** `init --ci gitlab --skip-existing` is run and every planned file exists
- **THEN** no file is written, each is listed as kept, and the exit code is 0

#### Scenario: Removed example restored without harm

- **WHEN** `init --ci gitlab --skip-existing` is run in a repository from which `configs/example.yaml` was removed and which holds `configs/prod.yaml`
- **THEN** `configs/example.yaml` is written and `configs/prod.yaml` is unchanged
- **AND** the next pipeline run skips the example as disabled, and its exit code depends only on `configs/prod.yaml`

#### Scenario: Skip and force together

- **WHEN** `init --ci gitlab --skip-existing --force` is run
- **THEN** the exit code is the usage error code, the message names both options, and no file is written

### Requirement: Narrow a run to groups of files

`init` SHALL accept a repeatable option naming a group: `pipeline`, `runner`, `base`, `example`, `editor` or `env`. With it, `init` SHALL act only on the selected files in the named groups. The CI system SHALL still be required. What other requirements say `init` writes describes a run that is not narrowed. The protection of existing files SHALL apply unchanged to the narrowed set.

#### Scenario: One group refreshed

- **WHEN** `init --ci gitlab --only runner --force` is run in a repository holding an edited `.gitlab-ci.yml`
- **THEN** `ci/run-configs.sh` is overwritten and listed
- **AND** `.gitlab-ci.yml` and every other file are unchanged

#### Scenario: Several groups

- **WHEN** `init --ci gitlab --only runner --only base --force` is run
- **THEN** `ci/run-configs.sh`, `.editorconfig` and `.gitattributes` are written and no other file is

#### Scenario: Narrowed run still protects existing files

- **WHEN** `init --ci gitlab --only base` is run and `.editorconfig` exists
- **THEN** the run fails listing `.editorconfig` and no file is written or changed
- **AND** a `.gitlab-ci.yml` that exists is not listed, because it is outside the narrowed set

#### Scenario: Group the selection leaves empty

- **WHEN** `init --ci gitlab --only editor` is run with no editor selected
- **THEN** the exit code is the usage error code, the message says the group selects no file, and no file is written

#### Scenario: Unknown group

- **WHEN** `init --ci gitlab --only docs` is run
- **THEN** the exit code is the usage error code, the message names `docs` and lists the groups, and no file is written

### Requirement: Stale pins named when writing

When `init` writes into a directory where a file `upgrade` would handle pins a version other than the running one, it SHALL warn on standard error, naming each such file and advising `upgrade`. It SHALL NOT change those files on account of the warning, and the warning SHALL NOT change the exit code. A digest on a pin naming the running version SHALL NOT count as stale.

#### Scenario: New file beside older pins

- **WHEN** `init --ci gitlab --editor intellij --skip-existing` is run by the tool at 0.4.0 where `.gitlab-ci.yml` pins image tag `0.3.0`
- **THEN** `.idea/jsonSchemas.xml` references the schema at `v0.4.0`
- **AND** standard error names `.gitlab-ci.yml` and advises `upgrade`
- **AND** `.gitlab-ci.yml` is unchanged and the exit code is 0

#### Scenario: Configuration file pins another version

- **WHEN** `init --ci gitlab --only base --force` is run by the tool at 0.4.0 where `configs/prod.yaml` references the schema at `v0.3.0`
- **THEN** standard error names `configs/prod.yaml` and advises `upgrade`

#### Scenario: Pins agree

- **WHEN** every pin in the directory names the running version, or the directory holds none of those files
- **THEN** no such warning is given

#### Scenario: Digest on the running version

- **WHEN** the pipeline pins `nexus-cleanup:0.4.0@sha256:<digest>` and the tool is at 0.4.0
- **THEN** no such warning names the pipeline

### Requirement: Check what init would do

`init` SHALL accept a check option. With it, `init` SHALL write nothing, create no directory, and print to standard output one line per planned file naming its path, group, state (`new`, `identical` or `differs`) and the action the same command would take without the option (`write`, `skip`, `overwrite` or `refuse`). The exit code SHALL be 0 unless the arguments are a usage error.

#### Scenario: Check beside the other options

- **WHEN** `init --ci gitlab --skip-existing --check` is run where `.editorconfig` matches its template, `.gitlab-ci.yml` was edited and `ci/run-configs.sh` is absent
- **THEN** standard output shows `.editorconfig` as `identical` and `skip`, `.gitlab-ci.yml` as `differs` and `skip`, and `ci/run-configs.sh` as `new` and `write`
- **AND** no file is written and the exit code is 0

#### Scenario: A run that would be refused

- **WHEN** `init --ci gitlab --check` is run with no other option and `.gitlab-ci.yml` exists
- **THEN** the action of every planned file is `refuse`, since that run would write nothing
- **AND** the exit code is 0

#### Scenario: Force previewed

- **WHEN** `init --ci gitlab --only runner --force --check` is run and `ci/run-configs.sh` exists
- **THEN** only `ci/run-configs.sh` is reported, with the action `overwrite`, and it is unchanged

#### Scenario: Target directory absent

- **WHEN** `init --ci gitlab --check cleanup-repo` is run and `cleanup-repo` does not exist
- **THEN** every planned file is `new` and `write`, and `cleanup-repo` is not created

#### Scenario: Usage errors still reported

- **WHEN** `init --check` is run without a CI system
- **THEN** the exit code is the usage error code

### Requirement: Check what upgrade would do

`upgrade` SHALL accept a check option. With it, `upgrade` SHALL write nothing and print to standard output one line for each file it would change. It SHALL give the same warnings as a run without the option. The exit code SHALL be 0 unless the arguments or the directory are a usage error.

#### Scenario: Stale pins reported

- **WHEN** `upgrade --check` is run in a repository whose pipeline pins an older version
- **THEN** standard output names the pipeline, the pipeline is unchanged, and the exit code is 0

#### Scenario: Nothing to upgrade

- **WHEN** `upgrade --check` is run and every pin names the running version
- **THEN** standard output is empty, standard error says nothing would change, and the exit code is 0

#### Scenario: Digest warning given

- **WHEN** `upgrade --check` is run where the pipeline pins an image by digest
- **THEN** the warning naming that line is given on standard error and the pipeline is unchanged

### Requirement: Reference configuration file

`init` SHALL write `configs/example.yaml`, beginning with a modeline referencing the pinned schema. The file SHALL be accepted by the tool's configuration loading and valid against the schema, SHALL set `disabled: true`, and SHALL select a placeholder repository that cannot exist. A comment SHALL say that it is a reference to copy.

#### Scenario: Example accepted and valid

- **WHEN** `configs/example.yaml` is loaded by the tool that wrote it and validated against the pinned schema
- **THEN** both accept it

#### Scenario: Unedited example does nothing

- **WHEN** the generated pipeline's dry-run job runs with a valid Nexus URL and `configs/example.yaml` unedited
- **THEN** the tool sends no request for that file and exits 0
- **AND** standard error says the file is disabled, and its report records that

#### Scenario: Example enabled before it is edited

- **WHEN** the `disabled` line is removed from `configs/example.yaml` and nothing else is changed, and the dry-run job runs
- **THEN** the job fails with an error naming the placeholder repository
- **AND** no deletion request is sent

#### Scenario: Example left beside real configurations

- **WHEN** `configs/` holds the unedited `configs/example.yaml` and `configs/prod.yaml`, and the tool exits 0 for `configs/prod.yaml`
- **THEN** the job ends with exit code 0

#### Scenario: Copy step documented

- **WHEN** an operator reads `configs/example.yaml`
- **THEN** a comment says to copy the file to a new name, name a real repository in the copy and remove its `disabled` line

## MODIFIED Requirements

### Requirement: Existing files are protected

Before writing, `init` SHALL check every path it would write. If any exists, it SHALL write nothing
and fail with a message listing every such path, unless the force option is given, in which case
it SHALL overwrite those paths, or the skip-existing option is given, in which case it SHALL keep
them and write the rest. It SHALL never remove or modify any other file.

#### Scenario: Conflict refused

- **WHEN** `init --ci gitlab` is run in a directory that already holds `.gitlab-ci.yml` and `.editorconfig`
- **THEN** the run fails listing both paths
- **AND** no file is written or changed

#### Scenario: Force overwrites only what init writes

- **WHEN** the same command is run with the force option and the directory also holds `configs/prod.yaml`
- **THEN** `.gitlab-ci.yml` and `.editorconfig` are overwritten and every other `init` file is written
- **AND** `configs/prod.yaml` is unchanged

#### Scenario: Skip-existing keeps what exists

- **WHEN** the same command is run with the skip-existing option and the directory also holds `configs/prod.yaml`
- **THEN** `.gitlab-ci.yml` and `.editorconfig` are unchanged and every other `init` file is written
- **AND** `configs/prod.yaml` is unchanged

### Requirement: Upgrade a configuration repository

The tool SHALL provide an `upgrade` subcommand that moves every version pin `init` writes, in the
files of a configuration repository that exist, to the tool's own version: image pins in the
pipeline, the Forgejo workflow's release tag, and the schema address in configuration files and
editor settings.

#### Scenario: Older repository upgraded

- **WHEN** `upgrade` is run in a repository written by `init` of an older release
- **THEN** every pin names the running tool's version and each changed file is listed
- **AND** apart from template content that changed between the two releases, the files are identical to what `init` of the running release writes with the same options

#### Scenario: Pin precision kept

- **WHEN** the pipeline pins the image as `nexus-cleanup:0.1`
- **THEN** after `upgrade` it pins the running release's `X.Y`

#### Scenario: Mirror prefix kept

- **WHEN** the pipeline pins the image as `nexus.corp:5000/bond-os/nexus-cleanup:0.1.0`
- **THEN** after `upgrade` the prefix is unchanged and the tag is the running version

#### Scenario: Digest pin replaced by a tag

- **WHEN** the pipeline pins the image as `nexus-cleanup:0.1.0@sha256:<digest>` or `nexus-cleanup@sha256:<digest>`
- **THEN** after `upgrade` each such pin is the running version's tag, without a digest
- **AND** a warning names each such line and advises re-adding a verified digest
- **AND** the exit code is 0

#### Scenario: Forgejo's Nushell moved with the tool

- **WHEN** the Forgejo workflow installs the x86_64 Nushell binary at an older `NU_VERSION`
- **THEN** after `upgrade` its `NU_VERSION` and `NU_SHA256` are those of the running release's own workflow

#### Scenario: Another Nushell binary left alone

- **WHEN** the Forgejo workflow installs a Nushell binary other than x86_64
- **THEN** `upgrade` leaves `NU_VERSION` and `NU_SHA256` unchanged and says they must be updated by hand

#### Scenario: Look-alikes untouched

- **WHEN** the GitLab pipeline names jobs `nexus-cleanup:dry-run`, `nexus-cleanup:execute` and `.nexus-cleanup:`
- **THEN** `upgrade` leaves those names unchanged

## REMOVED Requirements

### Requirement: Starting configuration file

**Reason**: The file shipped enabled so that an unedited repository failed naming its placeholder, which also stopped it being left beside real configurations. It is replaced by a disabled reference to copy.

**Migration**: Existing repositories keep their file. To adopt the new one, run `init --ci <system> --only example --force`, and move any real settings in the old file to a new file first.
