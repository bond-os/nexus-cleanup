# config-repository Specification

## Purpose

Lets an operator create the private repository a cleanup is run from — a pipeline for their CI
system, a starting configuration file and editor settings for schema completion — with every
version reference pinned consistently to the tool that wrote it.

## Requirements

### Requirement: Initialise a configuration repository

The tool SHALL provide an `init` subcommand that writes a configuration repository into a target
directory, the working directory unless another is given, creating the directory if it does not
exist. It SHALL read no run configuration, need no environment variable or credential, and make
no network request.

#### Scenario: Initialise without any configuration

- **WHEN** `init --ci gitlab` is run in an empty directory with no `NEXUS_URL`, credentials or configuration file
- **THEN** the repository files are written there and the exit code is 0
- **AND** no HTTP request is made

#### Scenario: Target directory given

- **WHEN** `init --ci gitlab cleanup-repo` is run and `cleanup-repo` does not exist
- **THEN** `cleanup-repo` is created and the files are written inside it

#### Scenario: Written files listed

- **WHEN** `init` writes files
- **THEN** standard error lists each written path relative to the target directory
- **AND** standard output is empty

### Requirement: CI system selection

`init` SHALL require exactly one CI system, chosen from `gitlab`, `forgejo`, `jenkins-docker` and
`jenkins-sh`, and SHALL write that system's pipeline at the path the system reads it from:
`.gitlab-ci.yml`, `.forgejo/workflows/nexus-cleanup.yml`, or `Jenkinsfile` for both Jenkins
variants. A missing or unknown choice SHALL be a usage error listing the choices, with nothing
written.

#### Scenario: GitLab selected

- **WHEN** `init --ci gitlab` is run
- **THEN** `.gitlab-ci.yml` is written and no other system's pipeline is

#### Scenario: Jenkins variant selected

- **WHEN** `init --ci jenkins-sh` is run
- **THEN** `Jenkinsfile` is written using plain `sh` steps rather than the Docker Pipeline plugin

#### Scenario: No CI system given

- **WHEN** `init` is run without a CI system
- **THEN** the exit code is the usage error code, the message lists the four choices, and no file is written

#### Scenario: Unknown CI system

- **WHEN** `init --ci github` is run
- **THEN** the exit code is the usage error code, the message names `github` and lists the four choices, and no file is written

### Requirement: Generated pipeline loops over the configuration directory

The pipeline SHALL hold a dry-run job and an execute job. Each SHALL run the tool once per
`configs/*.yaml` file in sorted order, continue past a failing file, write that file's report and
summary under `reports/`, fail when no file matches, and end with the first exit code other than
0 and 4, else 4 if any file returned it, else 0.

#### Scenario: Configuration added without a pipeline change

- **WHEN** a second file is added to `configs/` and the dry-run job runs
- **THEN** the tool runs once for each of the two files and a report is kept for each

#### Scenario: One failing file does not hide the others

- **WHEN** the tool exits 3 for the first of three files and 0 for the others
- **THEN** all three files are processed and their reports kept
- **AND** the job fails with exit code 3

#### Scenario: Skipped groups remain a warning

- **WHEN** the tool exits 4 for one file and 0 for the others
- **THEN** the job ends with exit code 4, which the pipeline treats as a warning rather than a failure

#### Scenario: Empty configuration directory

- **WHEN** `configs/` holds no `.yaml` file
- **THEN** the job fails with a message saying no configuration file was found

### Requirement: Generated pipeline never deletes without a person

The generated pipeline SHALL pass the execute flag only in its execute job, and that job SHALL
run only when a person starts it after the dry-run job. A scheduled or automatically triggered
pipeline SHALL perform dry runs only.

#### Scenario: Scheduled pipeline

- **WHEN** the generated pipeline runs on a schedule
- **THEN** only the dry-run job runs and no deletion request is sent

#### Scenario: Execute job is manual

- **WHEN** a pipeline's dry-run job has finished
- **THEN** the execute job waits for a person to start it

### Requirement: Versions pinned to the writing tool

Every version reference `init` writes SHALL be the exact version of the tool that writes it: the
image reference in the pipeline SHALL use tag `X.Y.Z`, never a floating tag, and every schema
reference SHALL point to `schema/config.schema.json` at release tag `vX.Y.Z`.

#### Scenario: Pins agree

- **WHEN** `init --ci gitlab --editor vscode --editor intellij` is run by the tool at version 0.3.0
- **THEN** the pipeline uses image tag `0.3.0`
- **AND** the example configuration file, the VS Code settings and the IntelliJ mapping all reference the schema at tag `v0.3.0`

### Requirement: Reference configuration file

`init` SHALL write `configs/example.yaml`, beginning with a modeline referencing the pinned
schema. The file SHALL be accepted by the tool's configuration loading and valid against the
schema, SHALL set `disabled: true`, and SHALL select a placeholder repository that cannot exist.
A comment SHALL say that it is a reference to copy.

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

### Requirement: Line endings and encoding fixed for the repository

`init` SHALL write an `.editorconfig` containing exactly `root = true` and a `[*]` section setting
`charset = utf-8` and `end_of_line = lf`, and a `.gitattributes` containing `* text=auto eol=lf`,
and nothing else in either file.

#### Scenario: Files written as specified

- **WHEN** `init --ci gitlab` is run
- **THEN** `.editorconfig` and `.gitattributes` exist with exactly that content

#### Scenario: Checkout on Windows keeps LF

- **WHEN** the generated repository is cloned with `core.autocrlf=true`
- **THEN** the pipeline file and every configuration file are checked out with LF line endings

### Requirement: Editor schema support on request

`init` SHALL write editor settings only for each editor requested, and none by default. For VS
Code it SHALL write `.vscode/settings.json` mapping the pinned schema to `configs/*.yaml` and
`configs/*.yml`, and `.vscode/extensions.json` recommending `redhat.vscode-yaml`. For IntelliJ-based
IDEs it SHALL write `.idea/jsonSchemas.xml` with the same mapping.

#### Scenario: No editor requested

- **WHEN** `init --ci gitlab` is run
- **THEN** neither `.vscode/` nor `.idea/` is created

#### Scenario: VS Code completion without a modeline

- **WHEN** the repository was initialised with `--editor vscode` and a new file without a modeline is created in `configs/`
- **THEN** VS Code with the recommended extension offers completion and validation from the pinned schema in that file

#### Scenario: IntelliJ mapping

- **WHEN** the repository was initialised with `--editor intellij` and opened in an IntelliJ-based IDE
- **THEN** files in `configs/` are validated against the pinned schema without further setup

#### Scenario: Unknown editor

- **WHEN** `init --ci gitlab --editor emacs` is run
- **THEN** the exit code is the usage error code, the message lists `vscode` and `intellij`, and no file is written

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

#### Scenario: Symlinks cannot redirect a write

- **WHEN** a planned path or one of its parent directories below the target directory is a symlink
- **AND** the command would write or overwrite that path
- **THEN** the command writes nothing, fails with a usage error naming the affected path
- **AND** the symlink target is unchanged
- **AND** `--check` reports the operation as `refuse` without writing

### Requirement: Keep existing files on request

`init` SHALL accept a skip-existing option. With it, `init` SHALL write the planned files that do
not exist, leave every planned file that exists unchanged, and list each kept path on standard
error. The exit code SHALL be 0 whether or not anything was written. Giving it together with the
force option SHALL be a usage error, with nothing written.

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

`init` SHALL accept a repeatable option naming a group: `pipeline`, `runner`, `base`, `example`,
`editor` or `env`. With it, `init` SHALL act only on the selected files in the named groups. The
CI system SHALL still be required. What other requirements say `init` writes describes a run that
is not narrowed. The protection of existing files SHALL apply unchanged to the narrowed set.

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

When `init` writes into a directory where a file `upgrade` would handle pins a version other than
the running one, it SHALL warn on standard error, naming each such file and advising `upgrade`. It
SHALL NOT change those files on account of the warning, and the warning SHALL NOT change the exit
code. A digest on a pin naming the running version SHALL NOT count as stale.

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

`init` SHALL accept a check option. With it, `init` SHALL write nothing, create no directory, and
print to standard output one line per planned file naming its path, group, state (`new`,
`identical` or `differs`) and the action the same command would take without the option (`write`,
`skip`, `overwrite` or `refuse`). The exit code SHALL be 0 unless the arguments are a usage error.

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

### Requirement: Generated pipeline URL fails loudly until replaced

A pipeline that sets the Nexus URL in the pipeline file itself SHALL set it to an address the
tool refuses as a placeholder, so that a pipeline run before the operator replaces it fails with
a usage error naming that address rather than with an API failure. A pipeline that reads the URL
from a CI variable SHALL NOT supply a default for it.

#### Scenario: Unedited GitLab or Jenkins pipeline

- **WHEN** the pipeline written by `init --ci gitlab`, `--ci jenkins-docker` or `--ci jenkins-sh` runs its dry-run job before its Nexus URL is edited
- **THEN** each configuration file's run exits 2 with a message naming the placeholder address
- **AND** no HTTP request is made

#### Scenario: Forgejo variable unset

- **WHEN** the pipeline written by `init --ci forgejo` runs without the repository variable `NEXUS_URL`, and no configuration file sets `url`
- **THEN** each configuration file's run exits 2 with the error for a missing `NEXUS_URL`

### Requirement: Environment tool support on request

`init` SHALL accept an environment-tool option whose one choice is `varlock`, and SHALL write
environment-tool files only when it is given, none by default. With `varlock` it SHALL write
`.env.schema` and `.gitignore`. An unknown choice SHALL be a usage error listing the choices,
with nothing written. The files SHALL be subject to the same protection of existing files as
every other file `init` writes.

#### Scenario: No environment tool requested

- **WHEN** `init --ci gitlab` is run
- **THEN** neither `.env.schema` nor `.gitignore` is written

#### Scenario: varlock requested

- **WHEN** `init --ci gitlab --env varlock` is run in an empty directory
- **THEN** `.env.schema` and `.gitignore` are written beside the other files and listed on standard error

#### Scenario: Unknown environment tool

- **WHEN** `init --ci gitlab --env dotenv` is run
- **THEN** the exit code is the usage error code, the message names `dotenv` and lists `varlock`, and no file is written

#### Scenario: Existing ignore file protected

- **WHEN** `init --ci gitlab --env varlock` is run in a directory that already holds `.gitignore`
- **THEN** the run fails listing `.gitignore` and no file is written or changed
- **AND** with the force option `.gitignore` is overwritten and every other file in the directory is unchanged

### Requirement: The varlock schema declares the connection settings without values

The written `.env.schema` SHALL declare `NEXUS_URL`, `NEXUS_USERNAME` and `NEXUS_PASSWORD`, and
no other variable. `NEXUS_URL` SHALL be required, typed as a URL and given no value.
`NEXUS_USERNAME` SHALL NOT be sensitive. `NEXUS_PASSWORD` SHALL be sensitive, required and
given no value. The file SHALL contain no address, credential or version pin.

#### Scenario: Nothing set

- **WHEN** an operator runs `varlock load` in a repository written with `--env varlock` without setting any value
- **THEN** varlock reports `NEXUS_URL` and `NEXUS_PASSWORD` as missing and starts no command

#### Scenario: Password masked

- **WHEN** the three values are set and `varlock load` is run
- **THEN** the password is shown masked and the URL and username in clear

#### Scenario: No placeholder to forget

- **WHEN** the written `.env.schema` is read
- **THEN** it contains no URL, no password value and no version number

### Requirement: Value files are ignored

The written `.gitignore` SHALL ignore varlock's value files — `.env`, `.env.local` and every
`.env.<name>.local` — and SHALL NOT ignore `.env.schema` or a per-environment file such as
`.env.production`, and SHALL contain nothing else.

#### Scenario: Local values never staged

- **WHEN** an operator creates `.env.local` and `.env.production.local` and runs `git add .`
- **THEN** neither file is staged

#### Scenario: Schema and environment files tracked

- **WHEN** an operator creates `.env.production` and runs `git add .`
- **THEN** `.env.production` and `.env.schema` are staged

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

### Requirement: Check what upgrade would do

`upgrade` SHALL accept a check option. With it, `upgrade` SHALL write nothing and print to standard
output one line for each file it would change. It SHALL give the same warnings as a run without the
option. The exit code SHALL be 0 unless the arguments or the directory are a usage error.

#### Scenario: Stale pins reported

- **WHEN** `upgrade --check` is run in a repository whose pipeline pins an older version
- **THEN** standard output names the pipeline, the pipeline is unchanged, and the exit code is 0

#### Scenario: Nothing to upgrade

- **WHEN** `upgrade --check` is run and every pin names the running version
- **THEN** standard output is empty, standard error says nothing would change, and the exit code is 0

#### Scenario: Digest warning given

- **WHEN** `upgrade --check` is run where the pipeline pins an image by digest
- **THEN** the warning naming that line is given on standard error and the pipeline is unchanged

### Requirement: Upgrade is local and contained

`upgrade` SHALL work in the working directory unless another is given, SHALL read and write no
file other than those whose pins it moves, and SHALL need no environment variable or credential
and make no network request. It SHALL list each file it changed and exit 0 whether or not
anything changed. An unknown option or an unusable directory SHALL be a usage error.

#### Scenario: Other files untouched

- **WHEN** the repository holds files `init` does not write, outside `configs/`
- **THEN** `upgrade` neither reads nor changes them

#### Scenario: Nothing to upgrade

- **WHEN** every pin already names the running version
- **THEN** no file is written, the command says nothing was changed, and the exit code is 0

#### Scenario: Unknown option

- **WHEN** `upgrade --execute` is run
- **THEN** the exit code is the usage error code and no file is written
