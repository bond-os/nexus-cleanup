# Grouping, strict ordering and keep/delete/skip decisions.
#
# The retention key is (repository, scope, group, name, variant). Scope keeps
# distribution releases from competing; variant keeps architectures from
# competing. Everything else about a decision follows from ordering the versions
# inside one such group — and refusing to order them when they cannot be ordered
# with confidence.

use ./versions.nu *
use ./variants.nu *
use ./scopes.nu *
use ./paths.nu *

export const DECISION_KEEP = "keep"
export const DECISION_DELETE = "delete"
export const DECISION_SKIP = "skip"

# Closed set of machine-readable reason codes.
export const REASON_GROUP_WITHIN_KEEP = "group-within-keep"
export const REASON_WITHIN_KEEP = "within-keep-window"
export const REASON_SUPERSEDED = "superseded"
export const REASON_UNORDERABLE = "group-unorderable"
export const REASON_AMBIGUOUS = "group-ambiguous"
export const REASON_OUTSIDE_PATTERN = "outside-pattern"

export const REASONS = [
    "group-within-keep"
    "within-keep-window"
    "superseded"
    "group-unorderable"
    "group-ambiguous"
    "outside-pattern"
]

def group-key [m: record]: nothing -> string {
    [$m.repository $m.scope $m.group $m.name $m.variant] | str join "\u{1f}"
}

def mark [rows: list<record>, decision: string, reason: string]: nothing -> list<record> {
    $rows | each {|r| $r | merge {decision: $decision, reason: $reason, rank: null} }
}

# Decide one group. The keep count is checked first: a group that cannot lose
# anything is never ordered, so formats with no usable version produce no skip
# noise.
def decide-group [
    rows: list<record>
    keep: int
    scheme_override: string
]: nothing -> list<record> {
    # The unit of retention is a component, except in a path-derived group, where
    # it is a distinct version: a directory is one item however many files it holds.
    let path_derived = ($rows | first | get path_derived)
    let units = if $path_derived { $rows | get version | uniq | length } else { $rows | length }

    if $units <= $keep {
        return (mark $rows $DECISION_KEEP $REASON_GROUP_WITHIN_KEEP)
    }

    let scheme = (version scheme-for-format ($rows | first | get format) $scheme_override)

    let unparseable = ($rows | where {|r| not (version parseable $scheme $r.version) })
    if ($unparseable | is-not-empty) {
        return (mark $rows $DECISION_SKIP $REASON_UNORDERABLE)
    }

    if $path_derived {
        return (decide-by-version $rows $keep $scheme)
    }

    let sorted = ($rows | sort-by --custom {|a, b| (version compare $scheme $a.version $b.version) > 0 })

    # Two distinct components whose versions compare equal cannot be ranked, so
    # the group is ambiguous rather than arbitrarily ordered.
    mut ambiguous = false
    for i in 0..<(($sorted | length) - 1) {
        let a = ($sorted | get $i | get version)
        let b = ($sorted | get ($i + 1) | get version)
        if (version compare $scheme $a $b) == 0 { $ambiguous = true }
    }
    if $ambiguous {
        return (mark $sorted $DECISION_SKIP $REASON_AMBIGUOUS)
    }

    $sorted
    | enumerate
    | each {|it|
        let rank = $it.index + 1
        if $rank <= $keep {
            $it.item | merge {decision: $DECISION_KEEP, reason: $REASON_WITHIN_KEEP, rank: $rank}
        } else {
            $it.item | merge {decision: $DECISION_DELETE, reason: $REASON_SUPERSEDED, rank: $rank}
        }
    }
}

# Rank the distinct versions of a path-derived group, then give every component
# its version's rank and decision. Many files sharing one version is expected;
# two distinct version strings comparing equal is still ambiguous.
def decide-by-version [rows: list<record>, keep: int, scheme: string]: nothing -> list<record> {
    let versions = ($rows | get version | uniq | sort-by --custom {|a, b| (version compare $scheme $a $b) > 0 })

    mut ambiguous = false
    for i in 0..<(($versions | length) - 1) {
        if (version compare $scheme ($versions | get $i) ($versions | get ($i + 1))) == 0 { $ambiguous = true }
    }
    if $ambiguous {
        return (mark $rows $DECISION_SKIP $REASON_AMBIGUOUS)
    }

    let ranks = ($versions | enumerate | each {|it| {version: $it.item, rank: ($it.index + 1)} })
    $rows
    | each {|r|
        let rank = ($ranks | where version == $r.version | first | get rank)
        if $rank <= $keep {
            $r | merge {decision: $DECISION_KEEP, reason: $REASON_WITHIN_KEEP, rank: $rank}
        } else {
            $r | merge {decision: $DECISION_DELETE, reason: $REASON_SUPERSEDED, rank: $rank}
        }
    }
    | sort-by rank
}

# Expand components into one membership per variant, carrying the retention key.
# With a path pattern, a matching component is keyed by the extracted name and
# ordered by the extracted version; its metadata group and name play no part.
def memberships [
    components: list<record>
    repositories: record
    scope_pattern: string
    from_path: string
]: nothing -> list<record> {
    $components
    | each {|c|
        let repo_name = ($c.repository? | default "")
        let repo_config = ($repositories | get --optional $repo_name | default {})
        let scope = (scope of $c $repo_config --pattern $scope_pattern)
        let derived = if ($from_path | is-empty) { null } else { path match $c $from_path }
        variant of $c
        | each {|v| {
            repository: $repo_name
            format: ($c.format? | default "")
            scope: $scope
            group: (if $derived == null { $c.group? | default "" } else { "" })
            name: (if $derived == null { $c.name? | default "" } else { $derived.name })
            variant: $v
            version: (if $derived == null { $c.version? | default "" } else { $derived.version })
            component_id: ($c.id? | default "")
            path_derived: ($derived != null)
            component: $c
        } }
    }
    | flatten
}

# Group components and decide each one. Returns one record per group membership.
export def "policy plan" [
    components: list<record>
    --keep: int = 1
    --version-scheme: string = ""
    --scope-pattern: string = ""
    --repositories: record = {}    # repository name -> format-specific config
    --from-path: string = ""       # regex with (?P<name>...) and (?P<version>...)
]: nothing -> list<record> {
    if $keep < 1 {
        error make {msg: $"keep count must be at least 1, got ($keep)"}
    }
    if ($components | is-empty) { return [] }

    let all = (memberships $components $repositories $scope_pattern $from_path)

    # With a pattern, whatever it does not match is decided here, before any
    # grouping: no keep count or ordering outcome can ever reach it.
    let outside = if ($from_path | is-empty) { [] } else { $all | where not path_derived }
    let inside = if ($from_path | is-empty) { $all } else { $all | where path_derived }

    let decided = if ($inside | is-empty) { [] } else {
        $inside
        | group-by {|m| group-key $m }
        | values
        | each {|rows| decide-group $rows $keep $version_scheme }
        | flatten
    }
    $decided | append (mark $outside $DECISION_KEEP $REASON_OUTSIDE_PATTERN)
}

# Component ids safe to delete: a component is deletable only when every group
# it belongs to marked it for deletion.
export def "policy deletable-ids" [plan: list<record>]: nothing -> list<string> {
    $plan
    | group-by component_id
    | items {|id, rows| {id: $id, deletable: ($rows | all {|r| $r.decision == $DECISION_DELETE })} }
    | where deletable
    | get id
}
