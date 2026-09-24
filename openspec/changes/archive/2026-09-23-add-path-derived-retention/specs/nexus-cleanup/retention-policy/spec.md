## ADDED Requirements

### Requirement: Path-derived retention

The policy SHALL accept a path pattern containing a `name` and a `version` named group and SHALL
apply it to every targeted repository, whatever its format. For each component whose asset
path matches the pattern, the extracted name SHALL replace the metadata group/namespace and
name in the retention key, and the extracted version SHALL replace the metadata version for
ordering. Every component whose path falls under a matched location SHALL belong to that
location's retention unit, however deeply it is nested.

#### Scenario: Version taken from the path

- **WHEN** a raw component with an empty metadata version lives at `/some_dir/20250103/app.tar.gz` and the pattern extracts `20250103` as its version
- **THEN** it is ordered as version `20250103`

#### Scenario: Nested files belong to their directory's unit

- **WHEN** files at `/some_dir/20250103/app.tar.gz` and `/some_dir/20250103/docs/readme.txt` both match with version `20250103`
- **THEN** both belong to the same retention unit and share one decision

#### Scenario: Pattern applies to any format

- **WHEN** a path pattern is supplied for a repository whose format is not raw
- **THEN** components whose paths match are grouped and versioned by the pattern exactly as raw components would be

### Requirement: Components outside the path pattern are never deleted

When a path pattern is supplied, every component whose asset path does not match it SHALL be
retained, SHALL belong to no retention group, and SHALL be reported with a reason identifying it
as outside the pattern. No keep count, ordering outcome or other rule SHALL mark such a component
for deletion. When no path pattern is supplied, no component SHALL carry that reason.

#### Scenario: Version directories beside date directories are untouched

- **WHEN** a pattern matches only date-named directories and `/some_dir/3.2.4.24-something/app.tar.gz` sits beside them
- **THEN** that component is kept with the outside-pattern reason
- **AND** it is not counted towards the keep count of the date directories

#### Scenario: Files outside any matched directory are untouched

- **WHEN** a component lives at `/some_dir/app.tar.gz`, directly under a parent the pattern names but in no matched subdirectory
- **THEN** it is kept with the outside-pattern reason

#### Scenario: Outside-pattern retention survives any keep count

- **WHEN** the keep count is 1 and many unmatched components exist
- **THEN** every unmatched component is still kept

#### Scenario: No pattern, no outside-pattern reason

- **WHEN** a run is made without a path pattern
- **THEN** no record carries the outside-pattern reason

### Requirement: Date version scheme

The policy SHALL provide a `date` version scheme, selected only explicitly. A version parses
under it when it begins with eight digits forming a real calendar date in `YYYYMMDD` form,
optionally followed by a suffix that does not begin with a digit. Versions SHALL be ordered
first by date; for the same date the bare date SHALL rank below every suffixed version, and
suffixed versions SHALL be ordered naturally, comparing digit runs numerically and other text
character by character.

#### Scenario: Chronological order across years

- **WHEN** a group holds `20241231`, `20250101` and `20250102`
- **THEN** the ordering from newest is `20250102`, `20250101`, `20241231`

#### Scenario: Same-day respin ranks above the bare date

- **WHEN** a group holds `20250103` and `20250103-hotfix`
- **THEN** `20250103-hotfix` is ordered as newer

#### Scenario: Respins ordered naturally

- **WHEN** a group holds `20250103-hotfix2` and `20250103-hotfix10`
- **THEN** `20250103-hotfix10` is ordered as newer

#### Scenario: Suffix without a separator

- **WHEN** a version is `20250103hotfix`
- **THEN** it parses under the date scheme and orders as a respin of `20250103`

#### Scenario: Leap day accepted

- **WHEN** a version is `20240229`
- **THEN** it parses under the date scheme

#### Scenario: Impossible dates rejected

- **WHEN** a group holding more units than the keep count contains `20250229` or `20251399`
- **THEN** the version does not parse under the date scheme
- **AND** the group is reported as skipped and nothing in it is deleted

#### Scenario: Non-date versions rejected

- **WHEN** a version is `3.2.5`, `2025010` or `202501011`
- **THEN** it does not parse under the date scheme

#### Scenario: Never chosen by default

- **WHEN** no version scheme is selected explicitly
- **THEN** the date scheme is not used for any repository format

## MODIFIED Requirements

### Requirement: Retention grouping

The policy SHALL partition components into groups keyed by the tuple
`(repository, scope, group/namespace, name, variant)`, where `scope` is the distribution,
release or repository section the component belongs to and `variant` is the architecture or
build variant derived for it. When the caller supplies a path pattern, a component whose asset
path matches it SHALL instead be keyed by `(repository, scope, path-name, variant)`, where
`path-name` is the name the pattern extracts; its metadata group/namespace and name play no
part in that key. Retention SHALL be evaluated independently inside each group, so that keeping
the newest version of one variant or scope never depends on the versions available for another.

Within a group the unit of retention is a component, except in a path-derived group, where it
is a distinct version: every component sharing one extracted version forms a single unit.

#### Scenario: Architectures retained independently

- **WHEN** a component name has versions 1.0 and 2.0 for variant `amd64` but only version 1.0 for variant `arm64`
- **THEN** `amd64` version 2.0 is kept and `amd64` version 1.0 is marked for deletion
- **AND** `arm64` version 1.0 is kept

#### Scenario: Same name in two repositories

- **WHEN** the same component name exists in two targeted proxy repositories
- **THEN** each repository forms its own groups and retention is decided separately per repository

#### Scenario: Releases retained independently

- **WHEN** a repository caches the same component name and architecture for two distribution releases, and the newer release holds a higher version
- **THEN** each release keeps its own newest version
- **AND** the older release's component is not deleted merely because a newer release has a higher version

#### Scenario: Namespaced names kept distinct

- **WHEN** two components share a name but differ in their group/namespace (for example a Maven groupId or an npm scope)
- **THEN** they form separate groups

#### Scenario: Files in different directories share a path-derived group

- **WHEN** a pattern extracts the name `some_dir` from both `/some_dir/20250101/a.tar.gz` and `/some_dir/20250102/b.tar.gz`
- **THEN** the two components belong to the same group, although their metadata names and groups differ

#### Scenario: Path-derived parents kept distinct

- **WHEN** a pattern extracts `some_dir` for one component and `some_other_dir` for another
- **THEN** they belong to different groups and are retained independently

### Requirement: Strict version ordering

The policy SHALL order the versions within a group using a version comparator selected for
the repository's format. Ordering SHALL be considered valid only when every version in the
group parses under the selected comparator and no two distinct retention units compare equal
— in an ordinary group no two distinct components, in a path-derived group no two distinct
version strings.
The comparator SHALL NOT fall back to timestamps, to Nexus' response order, or to plain
lexicographic string comparison.

#### Scenario: Numeric versions ordered

- **WHEN** a group holds versions 1.9.0, 1.10.0 and 1.10.0-rc1
- **THEN** the ordering from newest is 1.10.0, 1.10.0-rc1, 1.9.0

#### Scenario: Distribution version semantics honoured

- **WHEN** a group in an apt or yum repository holds versions `1:2.3-4` and `2.3-4`
- **THEN** the epoch-bearing version is ordered as newer, per that ecosystem's own comparison rules

#### Scenario: Comparator overridden by the caller

- **WHEN** the caller selects a version scheme explicitly
- **THEN** that comparator is used for every targeted repository regardless of format

#### Scenario: Files sharing a version are not ambiguous

- **WHEN** a path-derived group holds three files under one directory whose extracted version is `20250101`
- **THEN** the three files form one retention unit
- **AND** the group is not reported as ambiguous on their account

#### Scenario: Distinct version strings that compare equal remain ambiguous

- **WHEN** a path-derived group ordered with the generic scheme holds directories `1.0` and `1.0.0`
- **THEN** the group is reported as skipped with an ambiguity cause

### Requirement: Groups within the keep count are retained without ordering

The policy SHALL evaluate the keep count before it attempts to order a group. A group holding
`N` or fewer retention units has nothing to delete whatever its order, so the policy SHALL retain
every component in it and SHALL NOT report it as skipped, even when its versions could not
have been ordered.

#### Scenario: Unversioned format produces no skip noise

- **WHEN** a repository's components carry no usable version, and each group holds a single component with the keep count at 1
- **THEN** every component is reported as kept
- **AND** none is reported as skipped for being unorderable

#### Scenario: Small group with an unorderable version

- **WHEN** a group holds two components, one of them versioned `latest`, and the keep count is 2
- **THEN** both are reported as kept rather than skipped

#### Scenario: Ordering still applies above the keep count

- **WHEN** a group holds more retention units than the keep count and its versions cannot be ordered
- **THEN** the group is reported as skipped

#### Scenario: Path-derived group counted in directories

- **WHEN** a path-derived group holds 10 date directories totalling 30 files and the keep count is 14
- **THEN** all 30 files are reported as kept
- **AND** none is reported as skipped, even if one directory's version could not be ordered

### Requirement: Unorderable groups are left untouched

When a group holding more retention units than the keep count cannot have its versions validly
ordered, the policy SHALL keep every component in that group, mark each of them with a skipped
decision that names the cause, and SHALL NOT mark any component of that group for deletion.

#### Scenario: Unparseable version in the group

- **WHEN** a group holds versions 1.2.3, 1.3.0 and `latest`
- **THEN** all three components are reported as skipped because the group could not be ordered
- **AND** none of them is marked for deletion

#### Scenario: Ambiguous equal versions

- **WHEN** a group holds two distinct components whose versions compare as equal
- **THEN** the group is reported as skipped with an ambiguity cause
- **AND** neither component is marked for deletion

#### Scenario: One bad group does not block the rest

- **WHEN** one group in a repository is unorderable and the other groups are not
- **THEN** the unorderable group is skipped whole
- **AND** the remaining groups are still evaluated and produce deletion decisions

### Requirement: Keep count

The policy SHALL keep the newest `N` retention units of every validly ordered group, where
`N` defaults to 1 and is configurable per run, and SHALL mark every component outside those
units for deletion. `N` SHALL be at least 1; a group holding `N` or fewer retention units SHALL
have nothing marked for deletion.

#### Scenario: Default keeps only the newest

- **WHEN** a group holds four versions and no keep count is supplied
- **THEN** the newest version is kept and the other three are marked for deletion

#### Scenario: Configured keep count

- **WHEN** a group holds four versions and the keep count is 2
- **THEN** the two newest versions are kept and the other two are marked for deletion

#### Scenario: Group smaller than the keep count

- **WHEN** a group holds two versions and the keep count is 3
- **THEN** both versions are kept and nothing is marked for deletion

#### Scenario: Keep count below one refused

- **WHEN** a keep count of 0 or a negative keep count is supplied
- **THEN** the run fails with a configuration error before any component is enumerated

#### Scenario: Keep count counts directories, not files

- **WHEN** a path-derived group holds 16 date directories of 3 files each and the keep count is 14
- **THEN** the 42 files of the 14 newest directories are kept
- **AND** the 6 files of the 2 oldest directories are marked for deletion
