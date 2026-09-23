# The machine-parsable summary: per-decision records, the aggregate block, and
# the JSON and CSV encodings of them.
#
# Planning produces structured Nushell data; JSON and CSV are two encodings of
# the same table, produced at the last step, so neither can drift from the other.

use ./policy.nu *

# Column order for CSV. Documented and stable: consumers index by position, so a
# new field is only ever appended — never inserted.
export const FIELDS = [
    repository format scope group name variant version component_id
    decision reason rank size_bytes last_modified deleted error
    path
]

def sum-or-zero [xs: list<int>]: nothing -> int {
    if ($xs | is-empty) { 0 } else { $xs | math sum }
}

def total-size [component: record]: nothing -> int {
    sum-or-zero ($component.assets? | default [] | each {|a| $a.fileSize? | default 0 })
}

def first-path [component: record]: nothing -> string {
    $component.assets? | default [] | each {|a| $a.path? | default "" } | where {|p| $p | is-not-empty } | get --optional 0 | default ""
}

def newest-timestamp [component: record]: nothing -> string {
    let stamps = (
        $component.assets?
        | default []
        | each {|a| [($a.lastModified? | default ""), ($a.blobCreated? | default "")] }
        | flatten
        | where {|s| $s | is-not-empty }
    )
    if ($stamps | is-empty) { "" } else { $stamps | sort | last }
}

# One record per group membership. `outcomes` maps a component id to
# {deleted, error} for a run that actually deleted things.
export def "report records" [
    plan: list<record>
    outcomes: record = {}
]: nothing -> list<record> {
    $plan | each {|m|
        let outcome = ($outcomes | get --optional $m.component_id | default {})
        {
            repository: $m.repository
            format: $m.format
            scope: $m.scope
            group: $m.group
            name: $m.name
            variant: $m.variant
            version: $m.version
            component_id: $m.component_id
            decision: $m.decision
            reason: $m.reason
            rank: $m.rank
            size_bytes: (total-size $m.component)
            last_modified: (newest-timestamp $m.component)
            deleted: ($outcome.deleted? | default false)
            error: ($outcome.error? | default "")
            path: (first-path $m.component)
        }
    }
}

# A component spans one record per variant. Its effective decision: deleted only
# when every group agreed; skipped when any group could not be ordered.
def effective-decision [rows: list<record>]: nothing -> string {
    if ($rows | all {|r| $r.decision == $DECISION_DELETE }) { return $DECISION_DELETE }
    if ($rows | any {|r| $r.decision == $DECISION_SKIP }) { return $DECISION_SKIP }
    $DECISION_KEEP
}

# Strip any userinfo, so a URL carrying embedded credentials cannot reach the report.
def safe-url [url: string]: nothing -> string {
    if ($url | is-empty) { return "" }
    $url | str replace --regex '^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@' '${1}'
}

# The aggregate block. Counts are of distinct components, never of records.
export def "report summary" [records: list<record>, run: record]: nothing -> record {
    let components = (
        $records
        | group-by component_id
        | items {|id, rows| {
            id: $id
            decision: (effective-decision $rows)
            size: ($rows | first | get size_bytes)
            deleted: ($rows | any {|r| $r.deleted })
            failed: ($rows | any {|r| ($r.error | is-not-empty) })
        } }
    )

    let planned = ($components | where decision == $DECISION_DELETE)
    let failed = ($components | where failed)
    let deleted = ($components | where deleted)
    let grouped = ($records | where reason != $REASON_OUTSIDE_PATTERN)
    let groups = ($grouped | group-by {|r| [$r.repository $r.scope $r.group $r.name $r.variant] | str join "\u{1f}" })

    {
        mode: ($run.mode? | default "dry-run")
        started_at: ($run.started_at? | default "")
        finished_at: ($run.finished_at? | default "")
        nexus_url: (safe-url ($run.nexus_url? | default ""))
        repositories: ($run.repositories? | default [])
        keep: ($run.keep? | default 1)
        counts: {
            components_total: ($components | length)
            kept: ($components | where decision == $DECISION_KEEP | length)
            to_delete: (($planned | length) - ($failed | length))
            skipped: ($components | where decision == $DECISION_SKIP | length)
            failed: ($failed | length)
            deleted: ($deleted | length)
            groups_total: ($groups | columns | length)
            groups_skipped: (
                $groups
                | values
                | where {|rows| ($rows | any {|r| $r.decision == $DECISION_SKIP }) }
                | length
            )
        }
        bytes_reclaimable: (sum-or-zero ($planned | get size))
        bytes_reclaimed: (sum-or-zero ($deleted | get size))
    }
}

# The aggregate alone, as JSON. CSV output has nowhere to carry it, so the CLI
# writes it separately on request.
export def "report encode-summary" [summary: record]: nothing -> string {
    $summary | to json --indent 2
}

# Encode a report. JSON carries summary and records; CSV carries the records
# only, because a summary row inside the table would corrupt it for every
# ordinary CSV consumer.
export def "report encode" [report: record, --format: string = "json"]: nothing -> string {
    let records = ($report.records? | default [])
    match $format {
        "json" => ({summary: ($report.summary? | default {}), records: $records} | to json --indent 2)
        "csv" => (
            if ($records | is-empty) {
                ($FIELDS | str join ",") + "\n"
            } else {
                $records | select ...$FIELDS | to csv
            }
        )
        _ => (error make {msg: $"unknown report format '($format)'; expected json or csv"})
    }
}
