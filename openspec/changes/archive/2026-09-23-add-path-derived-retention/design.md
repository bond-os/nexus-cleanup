## Context

See `proposal.md` for motivation and the specs for the contract. The current pipeline this
change extends:

- `policy.nu` expands components into memberships keyed
  `(repository, scope, group, name, variant)`, groups them, then per group: keep-count check →
  parseability check → `sort-by --custom` → adjacent-equality (ambiguity) check → rank.
- `versions.nu` dispatches `generic` / `debian` / `rpm` through `version parseable` and
  `version compare`, and `SCHEMES` is the list `config.nu` validates against.
- `scopes.nu` already applies a caller-supplied regex with a named group to the first asset
  path — the same mechanism this change needs, one level up.
- raw components on the reference instance carry `group` = file directory, `name` = full file
  path, `version` = `""`, one asset each.

Nushell's `into datetime --format "%Y%m%d"` rejects impossible dates (`20250229`, `20251399`,
`20250100`) and accepts leap days (`20240229`), verified on 0.115.1. Calendar validation needs no
external binary.

## Goals / Non-Goals

**Goals:**

- Express "keep the newest N directories under each of these parents" for any layout a regex
  can describe, with the untouched-by-construction guarantee for everything the regex does not
  match.
- Leave behaviour without `--from-path` exactly as it is, including every existing test.

**Non-Goals:**

- Pattern presets or auto-detection of the date scheme from directory names.
- A separate include/exclude filter language. The pattern *is* the filter.

## Decisions

### A single pattern carries both name and version

`--from-path` must contain `(?P<name>…)` and `(?P<version>…)`. One expression means the two
can never disagree about which path segment is which, and it is validated once, up front.
`--scope-from-path` stays orthogonal — it still adds its dimension to the key, so an operator
can combine them.

*Alternative considered:* separate `--name-from-path` and `--version-from-path`. Rejected: two
patterns can match different subsets of components, creating a component with a path-derived
version but a metadata name, which has no sensible meaning.

### "Outside the pattern" is decided before grouping, and is final

When `--from-path` is set, unmatched components never enter `memberships` for grouping. They
are emitted straight as `keep` / `outside-pattern`, so no later rule — keep count, ordering,
the multi-variant "every group agrees" check — can even see them. This is the property the
motivating case depends on (the version directories must not be touched), so it is enforced
structurally rather than by a condition inside the decision logic.

*Alternative considered:* letting unmatched components fall through to their ordinary
metadata key. Rejected: for raw that yields one-file groups that are always kept anyway, but
for any other format it would silently mix pattern-based and metadata-based retention in one
run — an operator who wrote a pattern expects it to be the whole rule.

### Distinct-version ranking only in path-derived groups

Path-derived groups rank *distinct versions*: sort the unique version strings, assign ranks,
then give every component its version's rank and decision. Ambiguity is still detected — two
*distinct* version strings comparing equal (`1.0` / `1.0.0`) — but many files sharing one
string is the expected case, not an error.

Ordinary groups keep the existing component-level ranking and ambiguity rule untouched. In an
ordinary group two components sharing a version genuinely signals something the tool does not
understand, and the strict design says to stop there.

A membership carries a `path_derived` flag; `decide-group` branches on it once. The keep-count
pre-check counts units (`distinct versions` or `components`) through the same flag, which is
what makes "10 directories of 3 files, keep 14" a `group-within-keep` rather than an ordering
attempt.

### The `date` scheme

Parse: `^(?P<date>[0-9]{8})(?P<suffix>(?:[^0-9].*)?)$`, then `into datetime --format "%Y%m%d"`
must succeed. Compare: the 8-digit date as an integer (fixed width, so numeric order is
chronological); then bare before suffixed; then suffixes by a natural comparison — split into
digit and non-digit runs, digits numerically, text by code point, shorter-prefix first.

The natural comparator is new code, not a reuse of `debian-compare-part`: dpkg's rules give `~`
and letters special ranks that would surprise someone reading `-hotfix` versus `_2`, and coupling
the date scheme to Debian semantics would be accidental.

Selected only by `--version-scheme date`; `scheme-for-format` never returns it.

*Alternative considered:* extracting only the 8 digits as the version. Rejected: `20250103` and
`20250103-hotfix` would collapse into one unit, contradicting the confirmed rule that each
directory is one item.

### `path` is appended to the record

The record gains `path` — the first asset's path — appended after `error` in `FIELDS`. It is
populated for every record, not only path-derived ones: for raw it is the only human-readable
identity once `name` has been replaced by the pattern's `some_dir`, and for every other format
it is simply useful. Appending keeps every existing CSV column position.

### Where the pattern logic lives

A new `nexus-cleanup/paths.nu` exposes `path match [component, pattern] -> record | null`
(returning `{name, version}` or null). `policy.nu` calls it while building memberships. This
mirrors `scopes.nu` and keeps regex handling out of the decision logic.

## Risks / Trade-offs

- **A pattern that matches too much.** `(?P<name>[^/]+)` instead of an explicit
  `some_dir|some_other_dir` would sweep date-named directories anywhere at that depth into
  retention. → The report shows every matched record's `name`, the dry run is still the
  default, and the README example names the parents explicitly and says why.
- **A version-shaped directory that also looks like a date.** An 8-digit semver major such as
  `12345678.0.1`. → The recommended pattern requires the character after the eighth digit to be
  neither a digit nor a dot; the test suite pins that case.
- **`outside-pattern` inflates the kept count.** On a large repository with a narrow pattern
  most components are "kept" for a reason unrelated to retention. → The reason code makes it
  filterable; the aggregate is left unchanged rather than adding a count the spec does not ask
  for.
- **Existing CSV consumers asserting an exact column count** will see one more column. →
  Documented; positions are unchanged, which is what the reporting spec now promises.

## Migration Plan

Additive. Without `--from-path`, only the report changes, by the appended `path` column. Roll
out by dry-running the motivating repository, checking that every version directory reports
`outside-pattern` and that exactly the directories beyond the 14th newest per parent report
`delete`, then enabling `--execute` with a cap.

## Open Questions

None blocking. Whether to add an aggregate count for `outside-pattern` can wait for an operator
to ask for it; the per-record reason already carries the information.
