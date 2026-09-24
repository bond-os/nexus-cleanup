## Purpose

Provides authenticated, non-interactive, fully paginated access to the Nexus 3 REST API so
the cleanup can enumerate proxy repositories and their components and delete individual
components, with predictable behaviour when the server is slow, unreachable, or refuses a
request.

## ADDED Requirements

### Requirement: Credential and endpoint resolution

The client SHALL read its endpoint and credentials from the environment variables
`NEXUS_URL`, `NEXUS_USERNAME` and `NEXUS_PASSWORD`, authenticate with HTTP Basic
authentication, and SHALL NOT prompt for input on any code path. Credential values SHALL
NOT appear in the report, in diagnostics, or in error messages.

#### Scenario: Credentials taken from the environment

- **WHEN** `NEXUS_URL`, `NEXUS_USERNAME` and `NEXUS_PASSWORD` are set and the client issues a request
- **THEN** the request carries an HTTP Basic `Authorization` header built from those values
- **AND** no interactive prompt is produced

#### Scenario: Missing endpoint

- **WHEN** `NEXUS_URL` is unset or empty and no equivalent flag was supplied
- **THEN** the client reports a configuration error naming the missing variable
- **AND** no HTTP request is attempted

#### Scenario: Credentials never leak

- **WHEN** any request fails and the failure is reported
- **THEN** the emitted message contains neither the password nor the `Authorization` header value

### Requirement: Repository discovery restricted to proxy repositories

The client SHALL list repositories through the Nexus repositories endpoint and expose each
repository's name, format and type, and SHALL be able to retrieve a repository's
format-specific configuration where the retention policy needs it to determine that
repository's scope. Only repositories whose type is `proxy` SHALL be
eligible for cleanup; a caller-named repository of any other type SHALL be refused rather
than silently ignored.

#### Scenario: Proxy repository accepted

- **WHEN** the caller targets a repository whose type is `proxy`
- **THEN** the repository is accepted for component enumeration

#### Scenario: Hosted or group repository refused

- **WHEN** the caller names a repository whose type is `hosted` or `group`
- **THEN** the client refuses that repository with an error identifying its name and actual type
- **AND** no component of that repository is enumerated or deleted

#### Scenario: Format-specific configuration retrieved

- **WHEN** the policy needs a repository's declared distribution to scope its components
- **THEN** the client retrieves that repository's own configuration and exposes the declared value
- **AND** a repository whose configuration cannot be retrieved yields no declared value rather than an error that aborts the run

#### Scenario: Unknown repository name

- **WHEN** the caller names a repository that the Nexus instance does not expose
- **THEN** the client reports an error identifying the unknown name

### Requirement: Complete component enumeration via continuation tokens

The client SHALL enumerate components for a repository page by page, following the Nexus
continuation token until the server returns none, and SHALL return every component from
every page. A truncated enumeration SHALL be treated as an error, never as an empty or
partial result set that could cause components to be judged obsolete.

#### Scenario: Multi-page enumeration

- **WHEN** a repository's components span three pages and each response but the last carries a continuation token
- **THEN** the client issues follow-up requests until no token remains
- **AND** the returned set contains the components of all three pages exactly once

#### Scenario: Failure mid-enumeration

- **WHEN** a page request fails after earlier pages succeeded
- **THEN** the client reports an enumeration failure for that repository
- **AND** the partial component set is not used to make retention decisions for that repository

#### Scenario: Empty repository

- **WHEN** a proxy repository holds no components
- **THEN** the client returns an empty set without error

### Requirement: Component deletion

The client SHALL delete a component by its Nexus component identifier and SHALL treat a
successful deletion response as authoritative. A deletion that fails SHALL be reported per
component and SHALL NOT abort the remaining work.

#### Scenario: Successful deletion

- **WHEN** deletion of a component identifier returns a success status
- **THEN** the component is recorded as deleted

#### Scenario: Component already gone

- **WHEN** deletion returns a not-found status
- **THEN** the component is recorded as deleted with a note that it was already absent
- **AND** the run is not marked as failed on account of it

#### Scenario: Deletion refused

- **WHEN** deletion returns an authorization or server error status
- **THEN** that component is recorded as failed with the status and server message
- **AND** the remaining components continue to be processed

### Requirement: Transient failure handling

The client SHALL retry a request that fails with a transport error or a retryable HTTP
status (429 or 5xx) using bounded exponential backoff, up to a configurable maximum number
of attempts, and SHALL NOT retry a request that failed with a non-retryable status such as
400, 401, 403 or 404. Every request SHALL be subject to a configurable timeout.

#### Scenario: Retry on a retryable status

- **WHEN** a request returns 503 and the attempt limit has not been reached
- **THEN** the request is retried after a backoff delay

#### Scenario: No retry on authentication failure

- **WHEN** a request returns 401
- **THEN** the client fails immediately without retrying

#### Scenario: Attempt limit exhausted

- **WHEN** every attempt of a request fails with a retryable status
- **THEN** the client reports the failure including the final status and the number of attempts made

### Requirement: Version-independent response handling

The client SHALL parse Nexus responses tolerantly rather than against a fixed schema: fields
it does not recognise SHALL be ignored, documented fields that are absent SHALL be treated as
absent rather than as an error, and no behaviour SHALL be selected by inspecting the Nexus
version. The client SHALL NOT depend on request parameters that only some Nexus versions
honour, including any page-size parameter, and SHALL derive paging solely from the
continuation token the server returns.

#### Scenario: Unknown fields ignored

- **WHEN** a response contains component or asset fields the client does not know about
- **THEN** the response is processed normally and the unknown fields are ignored

#### Scenario: Documented field absent

- **WHEN** a response omits an optional field such as a format-specific attribute map or an asset size
- **THEN** the client treats that field as absent
- **AND** the run continues rather than failing

#### Scenario: No version branching

- **WHEN** the client runs against instances of differing Nexus versions
- **THEN** it issues the same requests and applies the same parsing rules to each
- **AND** it does not query or condition on the server's version

#### Scenario: Paging independent of page size

- **WHEN** the server returns a page of any size, whether or not a page-size parameter was honoured
- **THEN** the client continues paging on the continuation token alone
- **AND** it does not assume a particular number of items per page
