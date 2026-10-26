# Spec Delta

## MODIFIED Requirements

### Requirement: Repository discovery and eligibility

The client SHALL list repositories through the Nexus repositories endpoint and expose each
repository's name, format and type, and SHALL be able to retrieve a repository's
format-specific configuration, from the endpoint matching the repository's type, where the
retention policy needs it to determine that repository's scope. A repository whose type is
`proxy` SHALL be eligible for cleanup. A repository whose type is `hosted` and whose format is
`raw` SHALL be eligible only when the caller both names it and allows hosted repositories.
Every other repository SHALL be ineligible, and a caller-named ineligible repository SHALL be
refused rather than silently ignored.

#### Scenario: Proxy repository accepted

- **WHEN** the caller targets a repository whose type is `proxy`
- **THEN** the repository is accepted for component enumeration

#### Scenario: Named raw hosted repository accepted with the opt-in

- **WHEN** the caller names a repository whose type is `hosted` and whose format is `raw`, and allows hosted repositories
- **THEN** the repository is accepted for component enumeration

#### Scenario: Hosted or group repository refused

- **WHEN** the caller names a repository whose type is `group`, with or without allowing hosted repositories, or whose type is `hosted` without allowing hosted repositories
- **THEN** the client refuses that repository with an error identifying its name and actual type
- **AND** for a hosted repository the error names the opt-in that would admit it
- **AND** no component of that repository is enumerated or deleted

#### Scenario: Hosted repository of another format refused

- **WHEN** the caller names a hosted repository whose format is not `raw` and allows hosted repositories
- **THEN** the client refuses that repository with an error identifying its name and format and stating that only raw hosted repositories are supported
- **AND** no component of that repository is enumerated or deleted

#### Scenario: Pattern never selects a hosted repository

- **WHEN** the caller selects by pattern, allows hosted repositories, and the pattern matches both a proxy and a raw hosted repository
- **THEN** only the proxy is selected

#### Scenario: Format-specific configuration retrieved

- **WHEN** the policy needs a repository's declared distribution to scope its components
- **THEN** the client retrieves that repository's own configuration from the endpoint for its type and exposes the declared value
- **AND** a repository whose configuration cannot be retrieved yields no declared value rather than an error that aborts the run

#### Scenario: Unknown repository name

- **WHEN** the caller names a repository that the Nexus instance does not expose
- **THEN** the client reports an error identifying the unknown name
- **AND** the error states that the repository either does not exist or is not visible to the authenticated user
