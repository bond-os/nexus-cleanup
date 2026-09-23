use ./harness.nu *
use ../nexus-cleanup/report.nu *
use ../nexus-cleanup/policy.nu *

def comp [repo: string, name: string, version: string, size: int]: nothing -> record {
    {
        id: $"($name)-($version)"
        repository: $repo
        format: "npm"
        group: ""
        name: $name
        version: $version
        assets: [{path: $"/($name)-($version).tgz", fileSize: $size, lastModified: "2026-01-02T03:04:05.000+00:00"}]
    }
}

def sample-plan []: nothing -> list<record> {
    policy plan [
        (comp "r" "w" "1.0.0" 100)
        (comp "r" "w" "2.0.0" 200)
        (comp "r" "w" "3.0.0" 300)
    ]
}

def sample-run []: nothing -> record {
    {
        mode: "dry-run"
        started_at: "2026-09-08T00:00:00+00:00"
        finished_at: "2026-09-08T00:00:10+00:00"
        nexus_url: "https://nexus.example.invalid"
        repositories: ["r"]
        keep: 1
    }
}

# The columns as they were before `path` was added: positions must never move.
const ORIGINAL_FIELDS = [
    repository format scope group name variant version component_id
    decision reason rank size_bytes last_modified deleted error
]
const FIELDS = [
    repository format scope group name variant version component_id
    decision reason rank size_bytes last_modified deleted error
    path
]

run-suite "report" [
    # --- record schema ---
    { name: "every documented field is present on every record", run: {||
        for r in (report records (sample-plan)) {
            for f in $FIELDS { assert ($f in ($r | columns)) }
        }
    } }
    { name: "records carry no leftover internal state", run: {||
        for r in (report records (sample-plan)) {
            assert not ("component" in ($r | columns))
        }
    } }
    { name: "inapplicable fields are present and empty, not omitted", run: {||
        let plan = (policy plan [(comp "r" "solo" "1.0.0" 10)])
        let r = (report records $plan | first)
        assert equal $r.rank null
        assert equal $r.error ""
        assert equal $r.group ""
        assert equal $r.deleted false
    } }
    { name: "size and timestamp are derived from the assets", run: {||
        let r = (report records (sample-plan) | where version == "2.0.0" | first)
        assert equal $r.size_bytes 200
        assert ($r.last_modified | str starts-with "2026-01-02")
    } }
    { name: "reason codes come from the closed set", run: {||
        for r in (report records (sample-plan)) { assert ($r.reason in $REASONS) }
    } }
    { name: "decisions come from the closed set", run: {||
        for r in (report records (sample-plan)) {
            assert ($r.decision in [$DECISION_KEEP $DECISION_DELETE $DECISION_SKIP])
        }
    } }
    { name: "execution outcomes are merged onto the matching records", run: {||
        let plan = (sample-plan)
        let outcomes = {"w-1.0.0": {deleted: true, error: ""}, "w-2.0.0": {deleted: false, error: "403 Forbidden"}}
        let records = (report records $plan $outcomes)
        assert equal ($records | where component_id == "w-1.0.0" | first | get deleted) true
        assert equal ($records | where component_id == "w-2.0.0" | first | get error) "403 Forbidden"
        assert equal ($records | where component_id == "w-3.0.0" | first | get deleted) false
    } }

    # --- aggregate ---
    { name: "counts sum to the component total", run: {||
        let records = (report records (sample-plan))
        let s = (report summary $records (sample-run))
        assert equal ($s.counts.kept + $s.counts.to_delete + $s.counts.skipped + $s.counts.failed) $s.counts.components_total
    } }
    { name: "each count matches the records", run: {||
        let records = (report records (sample-plan))
        let s = (report summary $records (sample-run))
        assert equal $s.counts.components_total 3
        assert equal $s.counts.kept 1
        assert equal $s.counts.to_delete 2
        assert equal $s.counts.skipped 0
        assert equal $s.counts.failed 0
    } }
    { name: "a multi-variant component is counted once", run: {||
        let multi = {
            id: "multi", repository: "r", format: "docker", group: "", name: "img", version: "1.0"
            assets: [
                {path: "/a", fileSize: 5, contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "amd64"}}
                {path: "/b", fileSize: 7, contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "arm64"}}
            ]
        }
        let plan = (policy plan [$multi])
        let records = (report records $plan)
        let s = (report summary $records (sample-run))
        assert equal ($records | length) 2
        assert equal $s.counts.components_total 1
    } }
    { name: "a dry run reports reclaimable but zero reclaimed bytes", run: {||
        let records = (report records (sample-plan))
        let s = (report summary $records (sample-run))
        assert equal $s.bytes_reclaimable 300
        assert equal $s.bytes_reclaimed 0
    } }
    { name: "an executing run reports what was actually reclaimed", run: {||
        let outcomes = {"w-1.0.0": {deleted: true, error: ""}, "w-2.0.0": {deleted: true, error: ""}}
        let records = (report records (sample-plan) $outcomes)
        let s = (report summary $records (sample-run | merge {mode: "execute"}))
        assert equal $s.bytes_reclaimed 300
    } }
    { name: "a failed deletion is counted as failed, not as pending", run: {||
        let outcomes = {"w-1.0.0": {deleted: false, error: "500"}}
        let records = (report records (sample-plan) $outcomes)
        let s = (report summary $records (sample-run | merge {mode: "execute"}))
        assert equal $s.counts.failed 1
        assert equal $s.counts.to_delete 1
        assert equal ($s.counts.kept + $s.counts.to_delete + $s.counts.skipped + $s.counts.failed) $s.counts.components_total
    } }
    { name: "group counts are reported", run: {||
        let plan = (policy plan [
            (comp "r" "good" "1.0.0" 1)
            (comp "r" "good" "2.0.0" 1)
            (comp "r" "bad" "1.0.0" 1)
            (comp "r" "bad" "2.0.0" 1)
            (comp "r" "bad" "latest" 1)
        ])
        let s = (report summary (report records $plan) (sample-run))
        assert equal $s.counts.groups_total 2
        assert equal $s.counts.groups_skipped 1
    } }
    { name: "no credential appears anywhere in the report", run: {||
        let run = (sample-run | merge {nexus_url: "https://someone:hunter2@nexus.example.invalid"})
        let doc = (report encode {summary: (report summary (report records (sample-plan)) $run), records: (report records (sample-plan))})
        assert not ($doc | str contains "hunter2")
        assert not ($doc | str contains "someone")
    } }

    # --- JSON ---
    { name: "the default encoding is one parseable JSON document", run: {||
        let records = (report records (sample-plan))
        let doc = (report encode {summary: (report summary $records (sample-run)), records: $records})
        let parsed = ($doc | from json)
        assert ("summary" in ($parsed | columns))
        assert ("records" in ($parsed | columns))
        assert equal ($parsed.records | length) 3
    } }
    { name: "an empty run still emits a valid document", run: {||
        let doc = (report encode {summary: (report summary [] (sample-run)), records: []})
        let parsed = ($doc | from json)
        assert equal $parsed.records []
        assert equal $parsed.summary.counts.components_total 0
    } }

    # --- CSV ---
    { name: "CSV starts with a header naming every field in order", run: {||
        let records = (report records (sample-plan))
        let doc = (report encode {summary: (report summary $records (sample-run)), records: $records} --format csv)
        let header = ($doc | lines | first)
        assert equal $header ($FIELDS | str join ",")
    } }
    { name: "CSV has one row per record and no summary row", run: {||
        let records = (report records (sample-plan))
        let doc = (report encode {summary: (report summary $records (sample-run)), records: $records} --format csv)
        assert equal (($doc | lines | length) - 1) ($records | length)
        assert equal ($doc | from csv | length) ($records | length)
    } }
    { name: "values containing separators, quotes and newlines round-trip", run: {||
        let plan = (policy plan [(comp "r" "solo" "1.0.0" 1)])
        let nasty = 'he said "1,2" then' + "\n" + 'a new line'
        let records = (report records $plan {"solo-1.0.0": {deleted: false, error: $nasty}})
        let doc = (report encode {summary: (report summary $records (sample-run)), records: $records} --format csv)
        assert equal ($doc | from csv | first | get error) $nasty
    } }
    { name: "an empty record set still emits a CSV header", run: {||
        let doc = (report encode {summary: (report summary [] (sample-run)), records: []} --format csv)
        assert equal ($doc | lines | first) ($FIELDS | str join ",")
    } }
    { name: "path is appended, so every pre-existing column keeps its position", run: {||
        let doc = (report encode {summary: (report summary (report records (sample-plan)) (sample-run)), records: (report records (sample-plan))} --format csv)
        let header = ($doc | lines | first | split row ",")
        assert equal ($header | first ($ORIGINAL_FIELDS | length)) $ORIGINAL_FIELDS
        assert equal ($header | last) "path"
    } }
    { name: "every record carries its asset path", run: {||
        let r = (report records (sample-plan) | where version == "2.0.0" | first)
        assert equal $r.path "/w-2.0.0.tgz"
    } }
    { name: "a path-derived record names its parent but keeps the file path", run: {||
        let file = {id: "f", repository: "r", format: "raw", group: "/some_dir/20250101", name: "/some_dir/20250101/app.tar.gz", version: "", assets: [{path: "/some_dir/20250101/app.tar.gz", fileSize: 1}]}
        let plan = (policy plan [$file] --from-path '^/(?P<name>some_dir)/(?P<version>[0-9]{8})/' --version-scheme date)
        let r = (report records $plan | first)
        assert equal $r.name "some_dir"
        assert equal $r.path "/some_dir/20250101/app.tar.gz"
    } }
    { name: "outside-pattern components count as kept and the partition still holds", run: {||
        let layout = (open $"($env.FILE_PWD)/fixtures/raw/path-derived-layout.json" | get items)
        let plan = (policy plan $layout --from-path '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/' --version-scheme date --keep 14)
        let s = (report summary (report records $plan) (sample-run))
        let c = $s.counts
        assert equal $c.components_total 104
        assert equal $c.to_delete 12
        assert equal $c.kept 92
        assert equal ($c.kept + $c.to_delete + $c.skipped + $c.failed) $c.components_total
    } }
    { name: "outside-pattern components belong to no retention group", run: {||
        let layout = (open $"($env.FILE_PWD)/fixtures/raw/path-derived-layout.json" | get items)
        let plan = (policy plan $layout --from-path '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/' --version-scheme date --keep 14)
        let s = (report summary (report records $plan) (sample-run))
        assert equal $s.counts.groups_total 2
    } }
    { name: "an unknown format is refused", run: {||
        assert error {|| report encode {summary: {}, records: []} --format "yaml" }
    } }
]
