## Why

Two questions every operator meets are answered nowhere. First, what the tool's Nexus account
may do: without guidance it is usually given an admin role, which turns a stolen CI variable
into full control of the instance and leaves Nexus itself no part in the tool's guards. Second,
how to move a configuration repository to a newer release: the README says to bump every pin by
hand, but the schema address sits in every configuration file and in two editor settings files,
and a pin left behind silently validates files against the wrong release's schema.

## What Changes

- **README: a least-privilege section**, with the privileges taken from the four calls the tool
  makes — repository listing, component enumeration, component deletion and, for apt only, the
  repository's configuration — and an example role and user for each:
  - **Two users.** A browse-only user for the scheduled dry run, and a user that may also delete
    for the manual execute job, so that Nexus refuses a deletion that ever slipped past
    `--execute`. The section shows how each supported CI system gives the execute job its own
    credentials; the generated pipelines are not changed.
  - **Delete privileges per named repository.** Nexus privileges know a repository's format but
    not whether it is a proxy or hosted, so a wildcard such as `nx-repository-view-raw-*-delete`
    also covers raw hosted repositories and Nexus cannot back the tool's hosted guard. The
    section states the conflict with `--pattern` — a new proxy matching the pattern is selected,
    and its deletions fail with exit 1 until its privilege is added — and recommends naming the
    repositories.
  - **What a missing privilege looks like**: an invisible repository reads as unknown; without
    the apt configuration privilege the scope falls back to the implicit one, which changes only
    the report's label because an apt proxy serves one distribution.
  - Every privilege in the section is checked against the reference Nexus 3.96 instance before
    it is written, including whether enumeration needs `read` besides `browse`.
- **The unknown-repository error admits the other cause.** "Repository 'x' does not exist on
  this instance" becomes "does not exist, or this user cannot see it", because Nexus lists only
  the repositories the user has a privilege on.
- **README: upgrading a configuration repository.** One command, run from the *new* image with
  Nushell as the entrypoint, moves every schema address — modelines and `$schema` keys in
  `configs/`, `.vscode/settings.json`, `.idea/jsonSchemas.xml` — to the new release, matching
  any old version by pattern so that the command itself holds only the new version, one pin on
  its marked line. The same command moves the pipeline's image tag (or the Forgejo tag), and
  reading `CHANGELOG.md` and the diff before committing stays the advice. `init --force` remains
  the documented alternative, and a Renovate regex manager is named as the way to automate it in
  the operator's own repository.

Non-goals: changing the generated pipelines to take separate credentials; a tool subcommand that
rewrites pins; reading or checking the account's privileges at run time.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `nexus-cleanup/nexus-api-client`: "Repository discovery and eligibility" — the error for a
  named repository the instance does not expose also says the user may lack the privilege to
  see it.

## Impact

- **Code**: `nexus-cleanup/api.nu` (`api select-repositories` message); the tests asserting it.
- **Docs**: README gains "Nexus permissions" and "Upgrading" sections; "Getting started" points
  to the latter instead of describing the bump inline.
- **Release machinery**: the upgrade command's line carries an `x-release-please-version`
  marker; README is already an extra-file, so no configuration change is expected — confirmed
  when the line is written.
- **Verification**: needs the reference Nexus instance with a test role, not the hermetic suite.
