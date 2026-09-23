## Why

Some repositories encode what matters for retention in the *path*, not in component metadata.
The motivating case is a `raw` proxy laid out as `some_dir/<YYYYMMDD…>/…` beside
`some_dir/<semver-like>/…`, where the operator wants to keep the newest 14 date directories
per parent and never touch the version directories.

The tool cannot express that today — a dry run over that layout deletes nothing:

- Nexus gives each raw file its own identity: `name` is the full file path and `group` is the
  file's directory, both part of the retention key, so no two files ever compete.
- raw components carry an empty `version`; the version the operator means is a directory name.
- A directory holding several files yields several components with the same version, which
  strict ordering reports as `group-ambiguous` and skips.
- The `generic` comparator mis-orders suffixed dates (`20250103-hotfix` ranks *below*
  `20250103` by the semver pre-release rule) and cannot parse `20250103hotfix` at all.

## What Changes

- **Path-derived retention units.** A new `--from-path <regex>` option names, via
  `(?P<name>…)` and `(?P<version>…)` groups, the grouping name and the version of any component
  whose asset path it matches. For those components the pattern replaces the metadata `name`,
  `group` and `version` in the retention key.
- **Unmatched components are never deletion candidates.** When `--from-path` is given, every
  component whose path does not match is retained with a new, visible reason code
  `outside-pattern`. This is what guarantees that version directories beside the date
  directories are never touched.
- **Retention by distinct version for path-derived groups.** `--keep N` retains the newest `N`
  distinct versions; every component sharing a retained version is kept, every component of an
  older version is deleted. A directory is one item however many files it holds. The existing
  rule that equal versions make a group ambiguous is unchanged for ordinary groups.
- **A `date` version scheme**, selectable with `--version-scheme date`: an 8-digit `YYYYMMDD`
  that must be a real calendar date, optionally followed by a suffix. Same-day ordering puts the
  bare date first and suffixed respins after it in natural order. A matched version that is not
  a valid date makes its group unorderable, so nothing in it is deleted.
- **Report records gain a `path` field** (the asset path), appended after the existing fields so
  CSV column positions stay stable. Without it, a path-derived record — whose `name` is now the
  pattern's `some_dir` — would no longer say which file it is.

Target configuration for the motivating case:

```bash
nu nexus-cleanup.nu <raw-repo> \
  --from-path '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/' \
  --version-scheme date --keep 14
```

Non-goals: inferring the version scheme from the pattern, excluding repositories or paths by
any means other than the pattern itself, or deleting empty directories (Nexus has no directory
objects; a folder disappears from browse once its last component is gone).

## Capabilities

### New Capabilities
<!-- None: every behaviour here extends an existing capability. -->

### Modified Capabilities
- `nexus-cleanup/retention-policy`: the retention key gains a path-derived form; path-derived
  groups retain by distinct version; components outside the pattern are always retained; a new
  `date` version scheme.
- `nexus-cleanup/cli`: accepts and validates `--from-path`, and accepts `date` as a
  `--version-scheme`.
- `nexus-cleanup/reporting`: records carry the asset `path`, and `outside-pattern` joins the
  reason codes.

## Impact

- **Code**: `versions.nu` (new `date` scheme), a new `paths.nu` submodule for pattern matching,
  `policy.nu` (key selection, distinct-version ranking, `outside-pattern`), `report.nu`
  (`path` field, new reason), `config.nu` and the entrypoint (`--from-path` and its
  validation), `run.nu` (passing the pattern through).
- **Tests**: new suites for the `date` scheme and path-derived planning; extensions to the
  config, report, CLI and end-to-end suites; a recorded or synthetic raw fixture shaped like the
  motivating layout.
- **Compatibility**: without `--from-path`, behaviour and reports are unchanged apart from the
  appended `path` column. Consumers that address CSV columns by position are unaffected;
  consumers that assert an exact column count must accept the extra column.
- **Docs**: `README.md` (option, scheme, reason code, worked example) and `AGENTS.md` (standing
  decisions for the new rules).
