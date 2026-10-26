# Spec Delta

## ADDED Requirements

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
