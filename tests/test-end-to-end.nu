use ./harness.nu *
use ../nexus-cleanup/run.nu *
use ../nexus-cleanup/api.nu *
use ../nexus-cleanup/config.nu *
use ../nexus-cleanup/report.nu *

# Serves the recorded fixtures as if they were a live Nexus: multi-architecture
# apt, docker with an unorderable tag set, scoped yum, and version-bearing npm.
const REPOS = [
    [name, format, fixture];
    ["apt-proxy-deb.debian.org", "apt", "apt/apt-proxy-deb.debian.org-page-0.json"]
    ["docker-proxy-hub", "docker", "docker/docker-proxy-hub-page-0.json"]
    ["yum-proxy-resources.ovirt.org", "yum", "yum/yum-proxy-resources.ovirt.org-page-0.json"]
    ["npm-proxy-npm", "npm", "npm/npm-proxy-npm-page-0.json"]
    ["raw-dates", "raw", "raw/path-derived-layout.json"]
]

const DATE_DIRS = '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'

def run-dates [extra: record = {}]: nothing -> record {
    run-all ({from_path: $DATE_DIRS, version_scheme: "date", keep: 14} | merge $extra)
}

def fixtures-root []: nothing -> string { $"($env.FILE_PWD)/fixtures" }

def fixture-fetch [--delete-status: int = 204]: nothing -> closure {
    let root = (fixtures-root)
    let listing = ($REPOS | each {|r| {name: $r.name, format: $r.format, type: "proxy"}})
    let pages = ($REPOS | reduce --fold {} {|r, acc|
        $acc | insert $r.name (open $"($root)/($r.fixture)" | get items)
    })
    {|req|
        if $req.method == "DELETE" {
            {status: $delete_status, body: {}}
        } else if ($req.url | str contains "/repositories/apt/proxy/") {
            {status: 200, body: {apt: {distribution: "bookworm"}}}
        } else if ($req.url | str contains "/service/rest/v1/repositories/") {
            {status: 404, body: {}}
        } else if ($req.url | str contains "/service/rest/v1/repositories") {
            {status: 200, body: $listing}
        } else {
            let name = ($req.url | parse --regex 'repository=(?P<n>[^&]+)' | get n.0 | url decode)
            {status: 200, body: {items: ($pages | get $name), continuationToken: null}}
        }
    }
}

def run-all [extra: record = {}]: nothing -> record {
    let config = (config resolve ({
        url: "https://nexus.example.invalid"
        repositories: ($REPOS | get name)
    } | merge $extra))
    cleanup run $config (api client "https://nexus.example.invalid" --backoff 0ms --fetch (fixture-fetch))
}

run-suite "end to end" [
    { name: "the run completes over every recorded format", run: {||
        let out = (run-all)
        assert equal $out.exit_code $EXIT_OK
        assert equal ($out.report.summary.repositories | length) ($REPOS | length)
        assert equal $out.report.summary.counts.components_total (
            $REPOS | each {|r| open $"((fixtures-root))/($r.fixture)" | get items | length } | math sum
        )
    } }
    { name: "the report is a single parseable JSON document with every field", run: {||
        let out = (run-all)
        let parsed = ((report encode $out.report) | from json)
        assert ("summary" in ($parsed | columns))
        assert ("records" in ($parsed | columns))
        for r in ($parsed.records | first 25) {
            for f in $FIELDS { assert ($f in ($r | columns)) }
        }
    } }
    { name: "counts are internally consistent", run: {||
        let c = (run-all | get report | get summary | get counts)
        assert equal ($c.kept + $c.to_delete + $c.skipped + $c.failed) $c.components_total
    } }

    # --- multi-architecture apt ---
    { name: "apt keeps the newest version of each architecture", run: {||
        let rows = (run-all | get report.records | where repository == "apt-proxy-deb.debian.org")
        assert equal ($rows | where decision == "keep" | get version | uniq) ["2.10-5"]
        assert equal ($rows | where decision == "keep" | get variant | sort) ["amd64" "arm64"]
        assert equal ($rows | where decision == "delete" | length) 4
        assert equal ($rows | get scope | uniq) ["bookworm"]
    } }

    # --- docker with an unorderable tag set ---
    { name: "docker tag sets that cannot be ordered are skipped, not deleted", run: {||
        let rows = (run-all | get report.records | where repository == "docker-proxy-hub")
        let skipped = ($rows | where decision == "skip")
        assert greater ($skipped | length) 0
        assert equal ($skipped | get reason | uniq) ["group-unorderable"]
    } }
    { name: "docker variants distinguish an architecture from a multi-architecture index", run: {||
        let variants = (run-all | get report.records | where repository == "docker-proxy-hub" | get variant | uniq)
        assert ("amd64" in $variants)
        assert ("multiarch" in $variants)
    } }

    # --- scoped yum ---
    { name: "yum components carry a path-derived scope, not the implicit one", run: {||
        let rows = (run-all | get report.records | where repository == "yum-proxy-resources.ovirt.org")
        let scopes = ($rows | get scope | uniq)
        assert greater ($scopes | length) 1
        assert not ("*" in $scopes)
    } }

    # --- dry run versus execution ---
    { name: "a dry run and an executing run produce identical decisions", run: {||
        let dry = (run-all)
        let live = (run-all {execute: true, max_deletion_share: 1.0})
        let strip = {|rs| $rs | select repository scope name variant version decision reason rank | sort-by repository name variant version }
        assert equal (do $strip $dry.report.records) (do $strip $live.report.records)
    } }
    { name: "only the deleted flags and reclaimed bytes differ", run: {||
        let dry = (run-all)
        let live = (run-all {execute: true, max_deletion_share: 1.0})
        assert equal $dry.report.summary.counts.deleted 0
        assert equal $dry.report.summary.bytes_reclaimed 0
        assert equal $live.report.summary.counts.deleted $dry.report.summary.counts.to_delete
        assert equal $live.report.summary.bytes_reclaimed $dry.report.summary.bytes_reclaimable
        assert equal ($dry.report.records | where deleted | length) 0
        assert greater ($live.report.records | where deleted | length) 0
    } }

    # --- path-derived retention alongside the recorded repositories ---
    { name: "without a pattern the raw date layout is left entirely alone", run: {||
        let rows = (run-all | get report.records | where repository == "raw-dates")
        assert equal ($rows | get decision | uniq) ["keep"]
    } }
    { name: "with the pattern, only the oldest date directories are deleted", run: {||
        let rows = (run-dates | get report.records | where repository == "raw-dates")
        let deleted = ($rows | where decision == "delete" | each {|r| $"($r.name)/($r.version)" } | uniq | sort)
        assert equal $deleted ["some_dir/20250101" "some_dir/20250102" "some_other_dir/20240601" "some_other_dir/20240602"]
        assert equal ($rows | where reason == "outside-pattern" | length) 8
    } }
    { name: "the pattern never touches another repository's components", run: {||
        let rows = (run-dates | get report.records | where repository != "raw-dates")
        assert greater ($rows | length) 0
        assert equal ($rows | get reason | uniq) ["outside-pattern"]
        assert equal ($rows | get decision | uniq) ["keep"]
    } }
    { name: "path-derived dry and executing passes agree on every decision", run: {||
        let dry = (run-dates)
        let live = (run-dates {execute: true, max_deletion_share: 1.0})
        let strip = {|rs| $rs | select repository name version path decision reason rank | sort-by repository path }
        assert equal (do $strip $dry.report.records) (do $strip $live.report.records)
        assert equal $live.report.summary.counts.deleted 12
        assert equal $dry.report.summary.counts.deleted 0
    } }

    # --- CSV encoding of the same run ---
    { name: "the same run encodes to a CSV table that round-trips", run: {||
        let out = (run-all)
        let csv = (report encode $out.report --format csv)
        let parsed = ($csv | from csv)
        assert equal ($parsed | length) ($out.report.records | length)
        assert equal ($csv | lines | first) ($FIELDS | str join ",")
    } }
]
