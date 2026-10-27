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

### Requirement: Starting configuration file

`init` SHALL write `configs/example.yaml`, beginning with a YAML language server modeline that
references the pinned schema. The file SHALL be accepted by the tool's configuration loading and
valid against the schema, and SHALL select a placeholder repository that cannot exist, so that a
pipeline run before it is edited fails naming that placeholder. The file SHALL describe, in a
comment, how to disable it without deleting it.

#### Scenario: Example accepted and valid

- **WHEN** `configs/example.yaml` is loaded by the tool that wrote it and validated against the pinned schema
- **THEN** both accept it

#### Scenario: Unedited example fails loudly

- **WHEN** the generated pipeline runs before `configs/example.yaml` is edited
- **THEN** the dry-run job fails with an error naming the placeholder repository
- **AND** no deletion request is sent

#### Scenario: Disabling documented

- **WHEN** an operator reads `configs/example.yaml`
- **THEN** a comment shows `disabled: true` and states that it skips the file on every run until removed
- **AND** the key is commented out, so the unedited example is not disabled

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
it SHALL overwrite those paths. It SHALL never remove or modify any other file.

#### Scenario: Conflict refused

- **WHEN** `init --ci gitlab` is run in a directory that already holds `.gitlab-ci.yml` and `.editorconfig`
- **THEN** the run fails listing both paths
- **AND** no file is written or changed

#### Scenario: Force overwrites only what init writes

- **WHEN** the same command is run with the force option and the directory also holds `configs/prod.yaml`
- **THEN** `.gitlab-ci.yml` and `.editorconfig` are overwritten and every other `init` file is written
- **AND** `configs/prod.yaml` is unchanged

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
