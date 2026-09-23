## Purpose

Defines which cached components a cleanup run keeps and which it marks for deletion:
how components are grouped per repository, name and architecture variant, how versions
within a group are ordered, and when a group is left untouched because its versions cannot
be ordered with confidence.

## ADDED Requirements

### Requirement: Retention grouping

The policy SHALL partition components into groups keyed by the tuple
`(repository, scope, group/namespace, name, variant)`, where `scope` is the distribution,
release or repository section the component belongs to and `variant` is the architecture or
build variant derived for it. Retention SHALL be evaluated independently inside each group, so
that keeping the newest version of one variant or scope never depends on the versions
available for another.

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

### Requirement: Scope derivation per format

The policy SHALL derive each component's scope using a per-format rule, so that components
belonging to different distribution releases or repository sections never compete for
retention. A format whose layout offers no reliable signal SHALL use a single implicit scope
rather than a guessed one. The caller SHALL be able to override the rule for every targeted
repository by supplying a pattern that names the scope within the asset path; a component
whose path does not match SHALL fall back to the implicit scope.

The rule SHALL NOT derive a scope from any location that varies with the component's own
version, because doing so would place every version in its own group and silently retain
everything.

#### Scenario: Release and updates trees do not compete

- **WHEN** an rpm repository holds the same package and architecture under both a frozen release tree and an updates tree
- **THEN** the two are placed in different scopes
- **AND** each retains its own newest version

#### Scenario: Distribution taken from repository configuration

- **WHEN** a deb repository declares the distribution it proxies in its own configuration
- **THEN** that distribution is the scope for every component of that repository

#### Scenario: Format with no reliable scope signal

- **WHEN** a component's format offers no dependable release or section signal in its layout
- **THEN** every component of that repository shares one implicit scope
- **AND** retention behaves as though no scope dimension existed

#### Scenario: Version-bearing layout is not used as a scope

- **WHEN** a format stores each version of a component in its own directory
- **THEN** the directory is not used as the scope
- **AND** the versions of that component still compete for retention

#### Scenario: Caller-supplied scope pattern

- **WHEN** the caller supplies a pattern naming the scope within the asset path
- **THEN** that pattern determines the scope for every targeted repository
- **AND** a component whose path does not match the pattern receives the implicit scope

### Requirement: Variant derivation per format

The policy SHALL derive a component's variant from its assets using a per-format adapter.
An adapter SHALL first use the format's documented architecture attribute where the API
exposes one, then fall back to parsing the asset path or filename, and otherwise SHALL
assign the implicit single variant. A component whose assets disagree about the variant
SHALL be assigned every variant it carries, and a component that resolves to the implicit
variant SHALL be reported as such so an operator can see that no architecture split was
applied.

#### Scenario: Architecture read from an asset attribute

- **WHEN** a component's assets expose an architecture attribute of `arm64`
- **THEN** the component's variant is `arm64`

#### Scenario: Architecture parsed from a filename

- **WHEN** no architecture attribute is present but the asset filename encodes the architecture, as in `pkg_1.2.3_amd64.deb`
- **THEN** the component's variant is `amd64`

#### Scenario: Attribute map absent on an older instance

- **WHEN** a component's assets carry no format-specific attribute map, as on a Nexus version that does not expose one for that format, but the asset filename encodes the architecture
- **THEN** the derived variant is the same one the attribute would have produced

#### Scenario: Format without an architecture dimension

- **WHEN** the component's format exposes no architecture information at all
- **THEN** the component is assigned the implicit variant
- **AND** the emitted record shows the implicit variant rather than a guessed architecture

#### Scenario: Multi-architecture index carries every architecture

- **WHEN** a component's cached asset is a multi-architecture index rather than a single-architecture build, so it covers every architecture at once
- **THEN** the component is assigned the all-architectures variant
- **AND** that variant is distinguishable in the report from both a named architecture and the implicit variant

#### Scenario: Multi-architecture component

- **WHEN** a single component carries assets for both `amd64` and `arm64`
- **THEN** the component participates in the group of each of those variants
- **AND** the component is deleted only if it is marked for deletion in every group it belongs to

### Requirement: Strict version ordering

The policy SHALL order the versions within a group using a version comparator selected for
the repository's format. Ordering SHALL be considered valid only when every version in the
group parses under the selected comparator and no two distinct components compare equal.
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

### Requirement: Groups within the keep count are retained without ordering

The policy SHALL evaluate the keep count before it attempts to order a group. A group holding
`N` or fewer components has nothing to delete whatever its order, so the policy SHALL retain
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

- **WHEN** a group holds more components than the keep count and its versions cannot be ordered
- **THEN** the group is reported as skipped

### Requirement: Unorderable groups are left untouched

When a group holding more components than the keep count cannot have its versions validly
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

The policy SHALL keep the newest `N` versions of every validly ordered group, where `N`
defaults to 1 and is configurable per run, and SHALL mark every remaining component in that
group for deletion. `N` SHALL be at least 1; a group holding `N` or fewer components SHALL
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

### Requirement: Deletion decisions are derived, not incidental

Every component observed during a run SHALL receive exactly one decision — kept, marked for
deletion, or skipped — and no component SHALL be deleted without a decision recorded for it.
The set of decisions SHALL be identical for a dry run and for an executing run over the same
repository state.

#### Scenario: Every component accounted for

- **WHEN** a run enumerates a repository
- **THEN** the number of decision records equals the number of distinct components enumerated

#### Scenario: Dry run and execution agree

- **WHEN** the same repository state is processed once in dry-run mode and once in execute mode
- **THEN** both runs produce the same set of decisions
- **AND** only the executing run reports components as actually deleted
