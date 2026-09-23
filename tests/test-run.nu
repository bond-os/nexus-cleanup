use ./harness.nu *
use ../nexus-cleanup/run.nu *
use ../nexus-cleanup/api.nu *
use ../nexus-cleanup/config.nu *

# A Nexus that serves one npm proxy holding four versions of one package.
def stub-fetch [--delete-status: int = 204, --record-deletes: string = ""]: nothing -> closure {
    let repos = [
        {name: "npm-proxy", format: "npm", type: "proxy"}
        {name: "npm-hosted", format: "npm", type: "hosted"}
    ]
    let items = ([ "1.0.0" "1.1.0" "2.0.0" "3.0.0" ] | each {|v| {
        id: $"w-($v)", repository: "npm-proxy", format: "npm", group: "", name: "w", version: $v
        assets: [{path: $"/w-($v).tgz", fileSize: 100, lastModified: "2026-01-01T00:00:00.000+00:00"}]
    }})
    {|req|
        if ($req.method == "DELETE") {
            if ($record_deletes | is-not-empty) { $"($req.url)\n" | save --append --raw $record_deletes }
            {status: $delete_status, body: {}}
        } else if ($req.url | str contains "/service/rest/v1/repositories/") {
            {status: 404, body: {}}
        } else if ($req.url | str contains "/service/rest/v1/repositories") {
            {status: 200, body: $repos}
        } else {
            {status: 200, body: {items: $items, continuationToken: null}}
        }
    }
}

def cfg [extra: record = {}]: nothing -> record {
    config resolve ({url: "https://nexus.example.invalid", repositories: ["npm-proxy"]} | merge $extra)
}

def client-for [fetch: closure]: nothing -> record {
    api client "https://nexus.example.invalid" --backoff 0ms --fetch $fetch
}

def run-with [config: record, fetch: closure]: nothing -> record {
    cleanup run $config (client-for $fetch)
}

run-suite "run" [
    # --- dry run is the default ---
    { name: "no deletion request is issued without --execute", run: {||
        let log = (mktemp -t "deletes-XXXXXX")
        let out = (run-with (cfg) (stub-fetch --record-deletes $log))
        assert equal (open --raw $log | str trim) ""
        rm -f $log
        assert equal $out.report.summary.mode "dry-run"
        assert equal $out.report.summary.counts.to_delete 3
        assert equal $out.report.summary.counts.deleted 0
    } }
    { name: "no other flag implies execute", run: {||
        let log = (mktemp -t "deletes-XXXXXX")
        let config = (cfg {keep: 2, format: "csv", fail_on_skip: true, max_deletions: 100})
        run-with $config (stub-fetch --record-deletes $log)
        assert equal (open --raw $log | str trim) ""
        rm -f $log
    } }
    { name: "--execute deletes the planned components", run: {||
        let log = (mktemp -t "deletes-XXXXXX")
        let out = (run-with (cfg {execute: true}) (stub-fetch --record-deletes $log))
        let deleted = (open --raw $log | str trim | lines)
        assert equal ($deleted | length) 3
        rm -f $log
        assert equal $out.report.summary.mode "execute"
        assert equal $out.report.summary.counts.deleted 3
        assert equal $out.report.summary.bytes_reclaimed 300
    } }
    { name: "a dry run and an executing run agree on every decision", run: {||
        let dry = (run-with (cfg) (stub-fetch))
        let live = (run-with (cfg {execute: true}) (stub-fetch))
        let strip = {|rs| $rs | select component_id variant decision reason rank | sort-by component_id variant }
        assert equal (do $strip $dry.report.records) (do $strip $live.report.records)
        assert equal $dry.report.summary.counts.deleted 0
        assert equal $live.report.summary.counts.deleted 3
    } }

    # --- selection ---
    { name: "a non-proxy repository named explicitly is refused", run: {||
        let err = (try { run-with (cfg {repositories: ["npm-hosted"]}) (stub-fetch); null } catch {|e| $e })
        assert not equal $err null
        assert ($err.msg | str contains "hosted")
    } }
    { name: "a pattern matching nothing yields an empty report and success", run: {||
        let out = (run-with (cfg {repositories: [], pattern: "nothing-*"}) (stub-fetch))
        assert equal $out.exit_code $EXIT_OK
        assert equal $out.report.records []
        assert equal $out.report.summary.counts.components_total 0
    } }
    { name: "a pattern selects only proxies", run: {||
        let out = (run-with (cfg {repositories: [], pattern: "npm-*"}) (stub-fetch))
        assert equal $out.report.summary.repositories ["npm-proxy"]
    } }

    # --- deletion cap ---
    { name: "an over-cap executing run deletes nothing and signals the cap", run: {||
        let log = (mktemp -t "deletes-XXXXXX")
        let out = (run-with (cfg {execute: true, max_deletions: 2}) (stub-fetch --record-deletes $log))
        assert equal (open --raw $log | str trim) ""
        rm -f $log
        assert equal $out.exit_code $EXIT_CAP
        assert equal $out.report.summary.counts.to_delete 3
        assert equal $out.report.summary.counts.deleted 0
    } }
    { name: "the proportional cap also trips", run: {||
        # 3 of 4 components planned for deletion is above a half share.
        let out = (run-with (cfg {execute: true, max_deletion_share: 0.5}) (stub-fetch))
        assert equal $out.exit_code $EXIT_CAP
    } }
    { name: "a plan within the cap proceeds", run: {||
        let out = (run-with (cfg {execute: true, max_deletions: 3, max_deletion_share: 0.9}) (stub-fetch))
        assert equal $out.exit_code $EXIT_OK
        assert equal $out.report.summary.counts.deleted 3
    } }
    { name: "the cap does not affect a dry run", run: {||
        let out = (run-with (cfg {max_deletions: 1}) (stub-fetch))
        assert equal $out.exit_code $EXIT_OK
        assert equal $out.report.summary.counts.to_delete 3
    } }

    # --- exit codes ---
    { name: "a clean run exits zero", run: {||
        assert equal (run-with (cfg) (stub-fetch) | get exit_code) $EXIT_OK
    } }
    { name: "deletion failures exit one, and every component is still reported", run: {||
        let out = (run-with (cfg {execute: true}) (stub-fetch --delete-status 403))
        assert equal $out.exit_code $EXIT_DELETION_FAILURES
        assert equal $out.report.summary.counts.failed 3
        assert equal $out.report.summary.counts.components_total 4
        assert equal ($out.report.records | length) 4
    } }
    { name: "an unreachable Nexus raises rather than reporting success", run: {||
        let fetch = {|req| {status: 503, body: {}} }
        assert error {|| cleanup run (cfg) (api client "https://n.invalid" --max-attempts 1 --backoff 0ms --fetch $fetch) }
    } }
    { name: "skipped groups are tolerated by default", run: {||
        let versions = ([ "1.0.0" "2.0.0" "latest" ] | each {|v| {
            id: $"w-($v)", repository: "npm-proxy", format: "npm", group: "", name: "w", version: $v
            assets: [{path: "/w", fileSize: 1}]
        }})
        let fetch = {|req|
            if ($req.url | str contains "/service/rest/v1/repositories/") {
                {status: 404, body: {}}
            } else if ($req.url | str contains "/service/rest/v1/repositories") {
                {status: 200, body: [{name: "npm-proxy", format: "npm", type: "proxy"}]}
            } else {
                {status: 200, body: {items: $versions, continuationToken: null}}
            }
        }
        let tolerated = (cleanup run (cfg) (client-for $fetch))
        assert equal $tolerated.exit_code $EXIT_OK
        assert equal $tolerated.report.summary.counts.skipped 3
        let fatal = (cleanup run (cfg {fail_on_skip: true}) (client-for $fetch))
        assert equal $fatal.exit_code $EXIT_SKIPPED
    } }

    # --- path-derived retention end to end through the run ---
    { name: "an executing path-derived run deletes exactly the oldest directories", run: {||
        let items = (open $"($env.FILE_PWD)/fixtures/raw/path-derived-layout.json" | get items)
        let log = (mktemp -t "deletes-XXXXXX")
        let fetch = {|req|
            if $req.method == "DELETE" {
                $"($req.url)\n" | save --append --raw $log
                {status: 204, body: {}}
            } else if ($req.url | str contains "/service/rest/v1/repositories/") {
                {status: 404, body: {}}
            } else if ($req.url | str contains "/service/rest/v1/repositories") {
                {status: 200, body: [{name: "raw-dates", format: "raw", type: "proxy"}]}
            } else {
                {status: 200, body: {items: $items, continuationToken: null}}
            }
        }
        let config = (config resolve {
            url: "https://nexus.example.invalid"
            repositories: ["raw-dates"]
            from_path: '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'
            version_scheme: "date"
            keep: 14
            execute: true
        })
        let out = (cleanup run $config (client-for $fetch))
        let deleted = (open --raw $log | str trim | lines | each {|u| $u | split row "/service/rest/v1/components/" | last } | sort)
        rm -f $log

        let expected = (["some_dir/20250101" "some_dir/20250102" "some_other_dir/20240601" "some_other_dir/20240602"]
            | each {|d| ["app.tar.gz" "app.sha256" "docs/readme.txt"] | each {|f| $"raw-dates:/($d)/($f)" } }
            | flatten | sort)
        assert equal $deleted $expected
        assert equal $out.exit_code $EXIT_OK
        assert equal $out.report.summary.counts.deleted 12

        # No request ever touched a semver-like or top-level file.
        for u in $deleted {
            assert not ($u =~ '3\.2\.|12345678|app-at-top-level')
        }
    } }

    # --- stdout hygiene ---
    { name: "the run itself writes nothing to stdout", run: {||
        # Driven as a subprocess so stdout and stderr can be captured apart.
        let root = ($env.FILE_PWD | path dirname)
        let script = (mktemp -t "stdout-probe-XXXXXX.nu")
        [
            $"use ($root)/nexus-cleanup/run.nu *"
            $"use ($root)/nexus-cleanup/api.nu *"
            $"use ($root)/nexus-cleanup/config.nu *"
            "let fetch = {|req|"
            "    if ($req.url | str contains '/service/rest/v1/repositories/') {"
            "        {status: 404, body: {}}"
            "    } else if ($req.url | str contains '/service/rest/v1/repositories') {"
            "        {status: 200, body: [{name: 'r', format: 'npm', type: 'proxy'}]}"
            "    } else {"
            "        {status: 200, body: {items: [], continuationToken: null}}"
            "    }"
            "}"
            "let config = (config resolve {url: 'https://n.invalid', repositories: ['r']})"
            "cleanup run $config (api client 'https://n.invalid' --backoff 0ms --fetch $fetch) | ignore"
        ] | str join "\n" | save --force $script
        let result = (^$nu.current-exe $script | complete)
        rm -f $script
        assert equal $result.exit_code 0
        assert equal $result.stdout ""
        assert ($result.stderr | str contains "nexus-cleanup:")
    } }
]
