## 1. Repository scaffolding

- [x] 1.1 Add `.editorconfig` (`root = true`, `charset = utf-8`, `end_of_line = lf`) at the repository root and verify it is the only base config present, per the global convention
- [x] 1.2 Add `AGENTS.md` recording the project conventions: Nushell version floor and pinned container tag, module layout, test invocation, and the deliberate exceptions (no `uv`/Python here — this is a Nushell repository; deletion defaults to dry run; no Community Edition quota awareness) with their rationale
- [x] 1.3 Create the module skeleton `nexus-cleanup/{mod,config,api,variants,versions,policy,report}.nu` plus the `nexus-cleanup.nu` entrypoint, each exporting stubs, and verify `nu -c 'use nexus-cleanup'` succeeds and prints nothing (import is inert, per the CLI spec)
- [x] 1.4 Add `tests/run-tests.nu` that discovers and runs `tests/test-*.nu` via `std assert`, returning a non-zero exit code on failure, and verify it fails on a deliberately broken assertion and passes once removed

## 2. Version comparators (highest deletion risk — build first)

- [x] 2.1 Write failing tests for the `generic` comparator in `tests/test-versions-generic.nu`: dotted numeric cores of unequal length, semver pre-release ranking below its release, ignored build metadata, and unparseable inputs reported as such
- [x] 2.2 Implement `versions.nu` `compare-generic` and a `parse` predicate so the tests in 2.1 pass
- [x] 2.3 Write failing tests for the `debian` comparator using cases drawn from dpkg's own version-comparison corpus (epochs, `~` sorting before the empty string, alternating digit/non-digit segments, missing revision) in `tests/test-versions-debian.nu`
- [x] 2.4 Implement `compare-debian` so the tests in 2.3 pass
- [x] 2.5 Write failing tests for the `rpm` comparator using cases drawn from `rpmvercmp` test data (segment splitting, numeric vs alphabetic segments, `~` and `^`, epoch handling) in `tests/test-versions-rpm.nu`
- [x] 2.6 Implement `compare-rpm` so the tests in 2.5 pass
- [x] 2.7 Implement comparator selection by repository format with an explicit override, and verify by test that an apt repository gets `debian`, a yum repository gets `rpm`, an unknown format gets `generic`, and the override wins over all of them

## 3. API fixtures from the reference instance

- [x] 3.1 Inventory the local Nexus 3.96 Community Edition instance: list its repositories with format and type, and record in `AGENTS.md` which proxy formats already exist and which are missing from the set worth supporting
- [x] 3.2 Create an apt proxy repository on the reference instance and prime it with several versions of at least one package across two architectures, and prime the existing empty conan proxy, verifying through the Components API that each returns the expected components
- [x] 3.3 Write `tools/record-fixtures.nu` that walks the Repositories and Components APIs for named repositories and writes one JSON file per response page under `tests/fixtures/<format>/`, and verify it reproduces byte-identical output on a second run against unchanged repositories
- [x] 3.4 Implement redaction in the recorder — base URL and host, credentials, `uploader`, `uploaderIp`, the host portion of `downloadUrl`, and blob store names replaced with stable placeholders — and verify by test that a recorded fixture containing a known hostname and username comes out carrying neither
- [x] 3.5 Record and commit fixtures for every proxy repository on the reference instance, and add `tests/test-fixtures-clean.nu` asserting that no committed fixture contains a hostname, credential, uploader identity or IP address
- [x] 3.6 Document in `AGENTS.md` how to re-record fixtures against an upgraded Nexus and how to read the resulting diff, so a Nexus upgrade is a routine re-record rather than an investigation

## 4. Variant derivation

- [x] 4.1 Write failing tests for `variants.nu` against the recorded fixtures covering: architecture read from a format-specific asset attribute, architecture parsed from a filename such as `pkg_1.2.3_amd64.deb` and `pkg-1.2.3-1.el9.x86_64.rpm`, a format with no architecture dimension yielding the implicit variant, and a component carrying assets for two architectures yielding both
- [x] 4.2 Implement the adapter chain (documented attribute → filename/path parse → implicit variant) so the tests in 4.1 pass, and verify the implicit variant is a distinguishable value rather than an empty string
- [x] 4.3 Add a test that strips the format-specific attribute map from a recorded fixture — the older-instance case — and asserts the filename fallback derives the same variant the attribute produced
- [x] 4.4 Add a test against the recorded docker fixtures asserting that a single-architecture manifest yields its architecture, that a manifest list or OCI image index yields the all-architectures variant, and that the two are distinguishable from the implicit variant in the record

## 5. Retention policy

- [x] 5.0 Implement scope derivation in a `scopes.nu` submodule — asset directory for yum, the repository's declared `apt.distribution` for apt, the implicit scope elsewhere, and a `--scope-from-path` override — and verify by test against the recorded fixtures that a yum release tree and updates tree yield different scopes, that a maven-style version-bearing directory is never used as a scope, and that an unmatched path falls back to the implicit scope
- [x] 5.1 Write failing tests for grouping in `tests/test-policy-grouping.nu`: same name across two repositories, same name under different namespaces, per-architecture independence (the `amd64` 1.0/2.0 versus `arm64` 1.0 case from the spec), and per-scope independence (the same package and architecture under a release tree and an updates tree)
- [x] 5.2 Implement grouping by `(repository, scope, group, name, variant)` so the tests in 5.1 pass
- [x] 5.3 Write failing tests for strict ordering: a group containing `latest` alongside numeric versions is skipped whole, two distinct components with equal-comparing versions skip the group as ambiguous, and a skipped group does not prevent sibling groups from producing deletions
- [x] 5.4 Implement group ordering with `sort-by --custom` over the selected comparator plus the orderability check, so the tests in 5.3 pass
- [x] 5.5 Write failing tests for keep counts: default of 1, explicit 2, a group smaller than the keep count, and rejection of a keep count below 1
- [x] 5.6 Implement keep/delete marking with rank assignment so the tests in 5.5 pass
- [x] 5.7 Implement the keep-count check ahead of the orderability check, and verify by test that a group within the keep count is reported as kept rather than skipped even when its versions are unorderable, that an unversioned `raw`-style repository produces no skip noise, and that ordering still applies above the keep count
- [x] 5.8 Add a test asserting every enumerated component receives exactly one decision per group membership and that a multi-variant component is only marked for deletion when marked in every group it belongs to

## 6. Report

- [x] 6.1 Write failing tests for the record schema in `tests/test-report.nu`: every documented field present on every record, inapplicable fields present and empty, and reason codes drawn from the closed set
- [x] 6.2 Implement the record builder in `report.nu` so the tests in 6.1 pass
- [x] 6.3 Write failing tests for the aggregate block: counts summing to the component total, each count matching the records, dry-run reporting reclaimable but zero reclaimed bytes, and no credential value anywhere in the document
- [x] 6.4 Implement the aggregate builder so the tests in 6.3 pass
- [x] 6.5 Implement JSON encoding as the default and verify by test that the output parses as one document containing summary and records, including the empty-run case
- [x] 6.6 Implement CSV encoding and verify by test that the header names every field in the documented order, and that values containing commas, double quotes and newlines round-trip through `from csv`
- [x] 6.7 Implement `--summary-out` writing the aggregate as JSON to a path, and verify by test that stdout still holds only the CSV table

## 7. Nexus API client

- [x] 7.1 Implement the client record (base URL, credentials, timeout, retry policy, injectable `fetch` closure) and verify by test that constructing it makes no request
- [x] 7.2 Write failing tests for pagination against a `fetch` closure replaying recorded fixture pages: multiple pages consumed exactly once, an empty repository returning an empty set, and a mid-enumeration failure surfacing as an enumeration error rather than a partial set
- [x] 7.3 Implement continuation-token pagination over `GET /service/rest/v1/components` so the tests in 7.2 pass, sending no page-size parameter and making no assumption about items per page
- [x] 7.4 Write failing tests for tolerant parsing: a response carrying unknown component and asset fields is processed normally, and a response omitting an optional field such as a format-specific attribute map or an asset size is processed without error
- [x] 7.5 Implement tolerant parsing so the tests in 7.4 pass, and verify by inspection that no code path reads, requests or branches on the Nexus version
- [x] 7.6 Write failing tests for retry classification: retry on 429 and 5xx up to the attempt limit, no retry on 400/401/403/404, and the exhausted-attempts error naming the final status and attempt count
- [x] 7.7 Implement bounded exponential backoff and status classification so the tests in 7.6 pass
- [x] 7.8a Implement retrieval of a repository's format-specific configuration for scope derivation, and verify by test that a declared apt distribution is exposed and that a repository whose configuration cannot be retrieved yields no declared value rather than aborting the run
- [x] 7.8 Implement repository listing and proxy-type enforcement, and verify by test against the recorded repositories fixture that a `hosted` or `group` repository named explicitly is refused with its actual type and that an unknown name is refused
- [x] 7.9 Implement component deletion mapping success and not-found to deleted, and authorization/server errors to a per-component failure that does not abort the run; verify by test against a fixture `fetch`
- [x] 7.10 Add a test asserting that a failed request's rendered message contains neither the password nor the authorization header value

## 8. CLI and configuration

- [x] 8.1 Implement `config.nu` env/flag resolution and up-front validation, and verify by test that a flag overrides `NEXUS_URL`, that a missing URL aborts before any request, that a non-positive keep count, timeout or retry limit aborts with a usage error, and that an invalid or scope-less `--scope-from-path` pattern is refused before any repository is enumerated
- [x] 8.2 Implement repository selection by explicit names and by pattern in the entrypoint, and verify that no selection is a usage error, that non-proxy matches are excluded and reported, and that a pattern matching nothing yields an empty report and success
- [x] 8.3 Implement the dry-run default and the `--execute` opt-in, and verify by test that no deletion request is issued without `--execute` and that no other flag implies it
- [x] 8.4 Implement the deletion cap (absolute and proportional), and verify by test that an over-cap executing run deletes nothing, reports the full plan, and exits with the cap code, while a dry run over the cap is not a failure
- [x] 8.5 Implement `--fail-on-skip` and the exit-code mapping (0 success, 1 deletion failures, 2 usage/config, 3 API failure, 4 skipped-with-flag, cap code), and verify each code with a test driving the entrypoint against fixtures
- [x] 8.6 Route all progress and diagnostics to stderr and verify by test that stdout captured from a run contains only the report document

## 9. Packaging, CI and documentation

- [x] 9.1 Add a `Containerfile` (or documented base image tag) pinning the Nushell version, and verify the test suite passes inside that image
- [x] 9.2 Add a CI workflow running `tests/run-tests.nu` in the pinned image on every push, and verify it fails the build when a test fails
- [x] 9.3 Write `README.md` covering usage, environment variables, the dry-run default, exit codes, the report schema with its reason codes, the scope dimension and its per-format rules, the residual apt risk when `enforceDistribution` is false, the Docker/OCI variant rules, the reference Nexus version and the capability-probing approach to older instances, and the note that freed space appears only after Nexus' blob-store compaction task
- [x] 9.4 Add a CI job snippet to `README.md` showing a scheduled dry run whose JSON report is kept as an artifact, and a separate gated job that adds `--execute` with a cap

## 10. End-to-end verification

- [x] 10.1 Add an end-to-end test that runs the entrypoint against recorded fixtures covering an apt-style repository (multi-architecture), a maven-style repository and a docker-style repository with an unorderable tag set, asserting the full JSON report content
- [x] 10.2 Assert in that test that a dry run and an executing run over the same fixture state produce identical decision sets and differ only in the deleted flags and reclaimed byte total
- [x] 10.3 Run a dry run against the reference Nexus 3.96 instance, confirm the report matches what a manual inspection of those repositories shows, and re-record any fixture the run proves stale
- [x] 10.4 Run one executing pass with a conservative cap against a single expendable proxy repository on the reference instance, and verify from a follow-up enumeration that exactly the components the report named as deleted are gone
- [x] 10.5 Run `nu tests/run-tests.nu` in the pinned container and confirm the whole suite passes before the change is considered done
