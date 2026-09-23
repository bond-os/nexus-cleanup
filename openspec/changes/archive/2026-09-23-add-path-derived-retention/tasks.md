## 1. Date version scheme

- [x] 1.1 Write failing tests in `tests/test-versions-date.nu`: chronological order across months and years, bare date below its same-day respin, natural respin order (`-hotfix2` below `-hotfix10`), separator-less suffix parseable, leap day `20240229` accepted, `20250229` / `20251399` / `20250100` rejected, `3.2.5` / `2025010` / `202501011` rejected, and comparing an unparseable date raising rather than guessing
- [x] 1.2 Implement `date` parsing (eight digits + optional non-digit-initial suffix, calendar-validated with `into datetime --format "%Y%m%d"`) and comparison (date, then bare-before-suffixed, then natural suffix order) in `versions.nu`, add `date` to `SCHEMES`, and verify the tests in 1.1 pass
- [x] 1.3 Extend `tests/test-versions-scheme.nu` to verify `date` is accepted as an explicit override and that `version scheme-for-format` never returns it for any format, including `raw`

## 2. Path pattern matching

- [x] 2.1 Write failing tests in `tests/test-paths.nu` for `path match`: the motivating pattern extracts `{name, version}` from `/some_dir/20250101/app.tar.gz`, `/some_dir/20250103-hotfix/app.tar.gz`, `/some_dir/20250103hotfix/app.tar.gz` and a nested `/some_dir/20250103_2/nested/deep/file.bin`, and returns null for `/some_dir/3.2.4.24-something/app.tar.gz`, `/some_dir/3.2.5/app.tar.gz`, `/some_dir/12345678.0.1/app.tar.gz`, `/some_dir/2025010/app.tar.gz` and `/some_dir/app-at-top-level.tar.gz`; a component with no assets returns null
- [x] 2.2 Implement `nexus-cleanup/paths.nu` with `path match`, export it from `mod.nu`, and verify the tests in 2.1 pass and that `nu -c 'use nexus-cleanup'` still prints nothing

## 3. Retention policy

- [x] 3.1 Add a synthetic raw fixture `tests/fixtures/raw/path-derived-layout.json` shaped exactly like the recorded raw fixture (`group` = file directory, `name` = full path, `version` = `""`), holding for both `some_dir` and `some_other_dir`: 16 date directories of 3 files each (including a same-day respin and a separator-less suffix), 3 semver-like directories, and one file directly under the parent
- [x] 3.2 Write failing tests in `tests/test-policy-paths.nu`: with `--from-path` and `--version-scheme date --keep 14`, each parent keeps exactly its 14 newest directories' files and marks the 2 oldest directories' files for deletion; every semver-like and top-level file is `keep` / `outside-pattern` and is never deletable; the two parents are decided independently; the files of one directory share one rank and decision; 10 directories of 30 files at `--keep 14` report `group-within-keep`; an invalid calendar date in a group above the keep count skips the whole group; distinct strings `1.0` and `1.0.0` under the generic scheme still report `group-ambiguous`
- [x] 3.3 Implement the path-derived branch in `policy.nu` — unmatched components emitted as `keep` / `outside-pattern` before grouping, matched memberships keyed by `(repository, scope, path-name, variant)` with the extracted version and a `path_derived` flag, keep-count pre-check counting distinct versions, distinct-version ranking with ambiguity on distinct strings only — add `outside-pattern` to `REASONS`, and verify the tests in 3.2 pass
- [x] 3.4 Verify by running the full existing suite that behaviour without `--from-path` is unchanged, and add a test asserting that no record carries `outside-pattern` when no pattern is given

## 4. Report

- [x] 4.1 Append `path` (the first asset's path) after `error` in `FIELDS`, populate it for every record, and verify by test that every pre-existing CSV column keeps its position, that a path-derived record's `name` is the extracted name while its `path` is the file's own path, and that the report tests still pass
- [x] 4.2 Verify by test that `outside-pattern` records count as kept in the aggregate and that the aggregate's partition (kept + to_delete + skipped + failed = total) still holds with a pattern in use

## 5. CLI and configuration

- [x] 5.1 Add `from_path` to `config resolve` — must contain both `(?P<name>` and `(?P<version>` and must compile — and verify by test that a pattern missing either group or failing to compile is a usage error naming `--from-path`, that a valid pattern is accepted, and that `date` is accepted by `--version-scheme`
- [x] 5.2 Add `--from-path` to the entrypoint, pass it through `run.nu` to `policy plan`, and verify by an entrypoint test that an invalid pattern exits with the usage code before any request
- [x] 5.3 Extend `tests/test-run.nu` with a stubbed repository serving the synthetic layout, and verify that an executing run deletes exactly the components of the 2 oldest directories per parent and issues no deletion request for any semver-like or top-level file

## 6. End to end, docs and live verification

- [x] 6.1 Extend `tests/test-end-to-end.nu` with the synthetic raw repository alongside the recorded ones, and verify that the combined run's dry and executing passes agree on every decision and that the existing assertions for apt, docker, yum and npm are unchanged
- [x] 6.2 Document in `README.md` the `--from-path` option, the `date` scheme and its ordering rules, the `outside-pattern` reason, the appended `path` column, and the motivating configuration with the explicit parent list and the reason for the digit-or-dot guard
- [x] 6.3 Record in `AGENTS.md` the standing decisions: unmatched components are decided before grouping and never reach retention, distinct-version ranking applies only to path-derived groups, `date` is never chosen by default, and new record fields are only ever appended
- [x] 6.4 Stand up a raw proxy (or use an expendable existing one) on the reference instance holding a small version of the motivating layout, run a dry run with the motivating configuration, and confirm that every semver-like directory reports `outside-pattern` and exactly the directories beyond the configured keep count report `delete`
- [x] 6.5 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and confirm the whole suite passes
