# Spec Delta

## ADDED Requirements

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
