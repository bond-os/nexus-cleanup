## Why

Nexus 3 proxy repositories accumulate every version of every artifact they have ever
cached. Nothing evicts them: proxy cleanup policies in Nexus are age/usage based, not
version based, so a proxy that has mirrored a busy upstream for a year holds hundreds of
obsolete versions per component and grows without bound. Operators need a repeatable,
auditable job that keeps only the newest version(s) of each component — per architecture,
so an `arm64` consumer is not left without a package because the newest build happened to
be `amd64`.

The job has to run unattended in CI (a `nushell` container), so it must be safe by
default (dry-run), non-interactive, credential-driven from the environment, and it must
emit a machine-parsable summary that a later step can turn into a human report.

## What Changes

- New standalone repository content: a Nushell module `nexus-cleanup` plus a thin
  executable entrypoint script, runnable as `nu nexus-cleanup.nu ...` in an official
  `nushell` container image with no extra runtime dependencies.
- Component discovery over the Nexus 3 **Components REST API** (`GET /service/rest/v1/components`),
  format-agnostic, with cursor pagination handled internally.
- **Reference target Nexus 3.96 Community Edition**, with support for older instances by
  capability probing rather than version gating: every format-specific attribute is treated as
  optional, unknown fields are ignored, and nothing branches on a version number.
- Per-format **variant adapters** that derive an architecture/variant key from a component's
  assets (docker manifest architecture, deb/rpm `arch`, Maven classifier, …). Formats with
  no architecture dimension collapse to a single implicit variant.
- **Retention policy**: group components by `(repository, name, variant)`, order versions by
  a format-aware version comparison, keep the newest `N` (default 1), mark the rest for
  deletion.
- **Strict ordering**: if any two versions in a group cannot be ordered by the comparator,
  the whole group is skipped, reported as a warning, and nothing in it is deleted.
- **Dry-run by default**: deletion (`DELETE /service/rest/v1/components/{id}`) happens only
  when the operator passes an explicit execute flag.
- **Deletion cap circuit breaker**: an executing run whose plan exceeds a configured absolute
  or proportional cap aborts before deleting anything and reports the plan, so a misconfigured
  pattern or comparator change cannot quietly wipe a repository.
- **Machine-parsable summary** on stdout: JSON (default) or CSV (`--format csv`), one record
  per component decision (`keep` / `delete` / `skipped`) plus an aggregate counts block, so a
  downstream step can render a human-readable report.
- **Repository targeting**: explicit repository names and/or a name pattern, restricted to
  repositories whose `type` is `proxy` — hosted and group repositories are refused.
- A committed **fixture recorder** (`tools/record-fixtures.nu`) that captures real Components
  and Repositories API responses from a live Nexus, redacts host, credential and uploader
  identity data, and writes them to `tests/fixtures/`, so the test suite never needs a live
  Nexus and can be re-recorded when Nexus changes.
- Repository scaffolding required by the global conventions: `AGENTS.md`, `.editorconfig`,
  `README.md`.

Format coverage is set by what the reference instance can actually serve: a proxy repository is
stood up locally for every Community Edition format worth supporting, primed with several
versions, and recorded, so every fixture is real rather than hand-written from documentation.

Non-goals: rewriting Nexus' own cleanup policies, deleting blobs directly, compacting the
blob store (a separate Nexus task), supporting Nexus 2, or modelling Community Edition's
component and request quotas (see `design.md`).

## Capabilities

### New Capabilities
- `nexus-cleanup/nexus-api-client`: authenticated, paginated, non-interactive access to the
  Nexus 3 REST API — repository listing, component listing, component deletion, and the
  error/retry behaviour around them.
- `nexus-cleanup/retention-policy`: how components are grouped into `(repository, name, variant)`
  buckets, how variants are derived per format, how versions are ordered, and which ones are
  retained versus marked for deletion.
- `nexus-cleanup/cli`: the command-line surface — repository selection, `--keep`, dry-run
  versus execute, configuration precedence between environment variables and flags, and
  process exit codes.
- `nexus-cleanup/reporting`: the machine-parsable summary contract — the per-decision record
  schema, the aggregate counts, JSON and CSV encodings, and the separation of report data on
  stdout from diagnostics on stderr.

### Modified Capabilities
<!-- None: this is the first change in a greenfield repository. -->

## Impact

- **New code**: `nexus-cleanup/` module directory (`mod.nu` plus submodules for api, policy,
  variants, report) and a `nexus-cleanup.nu` entrypoint at the repository root.
- **New tests**: Nushell test scripts driving the pure functions (grouping, ordering,
  variant derivation, encoding) against recorded Nexus API fixtures; no live Nexus needed.
- **New tooling and data**: `tools/record-fixtures.nu` and the recorded, redacted
  `tests/fixtures/` tree, captured from a local Nexus 3.96 Community Edition instance that
  serves as the reference for every response shape the tool parses.
- **New docs/config**: `AGENTS.md`, `.editorconfig`, `README.md`, and a CI job example.
- **External systems**: read and write access to a Nexus 3 instance. Deletion is
  irreversible for the proxy cache — the artifacts are re-fetchable from upstream, which is
  what makes proxy repositories the safe place to do this, but an upstream that has yanked a
  version will not serve it again.
- **Credentials**: `NEXUS_URL`, `NEXUS_USERNAME`, `NEXUS_PASSWORD` read from the environment;
  never echoed into the report or diagnostics.
- **Runtime dependency**: Nushell (version pinned in `AGENTS.md`); no Python, no `curl`.
