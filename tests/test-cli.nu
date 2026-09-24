use ./harness.nu *
use ../nexus-cleanup/config.nu *
use ../nexus-cleanup/run.nu *
use ../nexus-cleanup/report.nu [FIELDS]

def entrypoint []: nothing -> string { $"($env.FILE_PWD | path dirname)/nexus-cleanup.nu" }

# Run the entrypoint with a clean environment so the developer's own .nexus.env
# cannot make a usage test pass by accident.
def cli [...args: string]: nothing -> record {
    with-env {NEXUS_URL: "", NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
        ^$nu.current-exe (entrypoint) ...$args | complete
    }
}

run-suite "cli" [
    { name: "no repository selection exits with the usage code", run: {||
        let r = (cli)
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "NEXUS_URL")
    } }
    { name: "an invalid keep count exits with the usage code before any request", run: {||
        let r = (cli "--url" "https://nexus.example.invalid" "--keep" "0" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "--keep")
    } }
    { name: "an invalid output format exits with the usage code", run: {||
        let r = (cli "--url" "https://nexus.example.invalid" "--format" "yaml" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--format")
    } }
    { name: "a scope pattern without a scope group exits with the usage code", run: {||
        let r = (cli "--url" "https://nexus.example.invalid" "--scope-from-path" "^/(x)" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--scope-from-path")
    } }
    { name: "an invalid path pattern exits with the usage code before any request", run: {||
        # The URL is unreachable: reaching it would exit with the API code instead.
        let r = (cli "--url" "http://127.0.0.1:9" "--from-path" "^/(?P<name>[^/]+)/" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "--from-path")
    } }
    { name: "an unreachable Nexus exits with the API code and writes no report", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec" "repo")
        assert equal $r.exit_code $EXIT_API
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "nexus-cleanup:")
    } }
    { name: "a usage failure names the setting without echoing the password", run: {||
        let r = (with-env {NEXUS_URL: "", NEXUS_PASSWORD: "hunter2"} {
            ^$nu.current-exe (entrypoint) "--url" "https://n.invalid" "--keep" "0" "repo" | complete
        })
        assert not ($r.stderr | str contains "hunter2")
    } }

    # --- summary-out alongside CSV (the aggregate CSV has no room for) ---
    { name: "CSV output writes the aggregate to the summary path, leaving stdout the table", run: {||
        let summary_path = (mktemp -t "summary-XXXXXX.json")
        let script = (mktemp -t "emit-probe-XXXXXX.nu")
        let root = ($env.FILE_PWD | path dirname)
        [
            $"use ($root)/nexus-cleanup/run.nu *"
            "let report = {"
            "    summary: {mode: 'dry-run', counts: {components_total: 1, kept: 1, to_delete: 0, skipped: 0, failed: 0, deleted: 0, groups_total: 1, groups_skipped: 0}}"
            "    records: [{"
            "        repository: 'r', format: 'npm', scope: '*', group: '', name: 'w', variant: '*'"
            "        version: '1.0.0', component_id: 'w-1', decision: 'keep', reason: 'group-within-keep'"
            "        rank: null, size_bytes: 10, last_modified: '', deleted: false, error: '', path: '/w-1.tgz'"
            "    }]"
            "}"
            $"cleanup emit $report 'csv' '($summary_path)'"
        ] | str join "\n" | save --force $script

        let r = (^$nu.current-exe $script | complete)
        rm -f $script
        assert equal $r.exit_code 0

        # stdout is the CSV table and nothing else
        let lines = ($r.stdout | str trim | lines)
        assert equal ($lines | first) ($FIELDS | str join ",")
        assert equal ($lines | length) 2
        assert not ($r.stdout | str contains "components_total")

        # the aggregate landed in the file, as JSON
        let summary = (open $summary_path)
        assert equal $summary.counts.components_total 1
        rm -f $summary_path
    } }
]
