# Orchestration: enumerate, plan, optionally delete, and report.
#
# Kept separate from the entrypoint so the whole flow can be driven in tests
# with an injected fetch closure, and so the entrypoint stays a thin shell that
# only parses flags and sets an exit code.

use ./api.nu *
use ./policy.nu *
use ./report.nu *
use ./config.nu *

def note [message: string] {
    # Diagnostics go to stderr; stdout carries the report and nothing else.
    print --stderr $"nexus-cleanup: ($message)"
}

def now []: nothing -> string {
    date now | format date "%+"
}

# Returns {report: {summary, records}, exit_code: int}.
export def "cleanup run" [config: record, client: record]: nothing -> record {
    let started_at = (now)

    let all_repositories = (api repositories $client)
    let selected = (api select-proxies $all_repositories $config.repositories --pattern $config.pattern)

    if ($selected | is-empty) {
        note "the selection matched no proxy repository"
        let summary = (report summary [] {
            mode: (if $config.execute { "execute" } else { "dry-run" })
            started_at: $started_at
            finished_at: (now)
            nexus_url: $config.url
            repositories: []
            keep: $config.keep
        })
        return {report: {summary: $summary, records: []}, exit_code: $EXIT_OK}
    }

    if ($config.pattern | is-not-empty) {
        let excluded = ($all_repositories | where type != "proxy" | where {|r| $r.name =~ (api glob-to-regex $config.pattern) })
        for r in $excluded {
            note $"excluding '($r.name)': it is a ($r.type) repository, not a proxy"
        }
    }

    mut components = []
    mut repo_configs = {}
    for repo in $selected {
        note $"enumerating ($repo.name) [($repo.format)]"
        $repo_configs = ($repo_configs | insert $repo.name (api repository-config $client $repo))
        $components = ($components | append (api components $client $repo.name))
    }

    let plan = (policy plan $components
        --keep $config.keep
        --version-scheme $config.version_scheme
        --scope-pattern $config.scope_pattern
        --from-path ($config.from_path? | default "")
        --repositories $repo_configs)

    let deletable = (policy deletable-ids $plan)
    let enumerated = ($components | length)

    # The cap is a circuit breaker for an executing run: a misconfigured pattern
    # or a comparator change must surface as a report, not as a mass deletion.
    let over_absolute = ($config.max_deletions > 0) and (($deletable | length) > $config.max_deletions)
    let over_share = ($config.max_deletion_share > 0.0) and ($enumerated > 0) and ((($deletable | length) | into float) / ($enumerated | into float) > $config.max_deletion_share)
    let capped = $config.execute and ($over_absolute or $over_share)

    mut outcomes = {}
    mut exit_code = $EXIT_OK

    if $capped {
        note $"deletion cap exceeded: ($deletable | length) of ($enumerated) components planned for deletion; nothing was deleted"
        $exit_code = $EXIT_CAP
    } else if $config.execute {
        note $"deleting ($deletable | length) components"
        for id in $deletable {
            let outcome = (api delete-component $client $id)
            $outcomes = ($outcomes | insert $id {deleted: $outcome.deleted, error: $outcome.error})
        }
    } else {
        note $"dry run: ($deletable | length) components would be deleted; pass --execute to delete them"
    }

    let records = (report records $plan $outcomes)
    let summary = (report summary $records {
        mode: (if $config.execute { "execute" } else { "dry-run" })
        started_at: $started_at
        finished_at: (now)
        nexus_url: $config.url
        repositories: ($selected | get name)
        keep: $config.keep
    })

    if $exit_code == $EXIT_OK {
        if $summary.counts.failed > 0 {
            $exit_code = $EXIT_DELETION_FAILURES
        } else if $config.fail_on_skip and ($summary.counts.skipped > 0) {
            $exit_code = $EXIT_SKIPPED
        }
    }

    {report: {summary: $summary, records: $records}, exit_code: $exit_code}
}

# Write the report: the document to stdout, and — when asked — the aggregate to
# a file, which is how CSV output carries a summary it has no room for.
export def "cleanup emit" [report: record, format: string, summary_out: string = ""] {
    if ($summary_out | is-not-empty) {
        report encode-summary $report.summary | save --force $summary_out
        note $"wrote the summary to ($summary_out)"
    }
    print (report encode $report --format $format)
}
