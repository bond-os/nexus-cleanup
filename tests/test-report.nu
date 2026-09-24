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
    { name: "multi-variant components resolve decisions and size correctly in summary", run: {||
        let records = [
            # Component 1: mixed delete + keep -> effective keep
            {repository: "r", format: "docker", scope: "*", group: "", name: "app1", variant: "amd64", version: "1.0", component_id: "c1", decision: "delete", reason: "superseded", rank: 2, size_bytes: 100, last_modified: "2026-01-01", deleted: false, error: "", path: "/app1-amd64"}
            {repository: "r", format: "docker", scope: "*", group: "", name: "app1", variant: "arm64", version: "1.0", component_id: "c1", decision: "keep", reason: "within-keep-window", rank: 1, size_bytes: 100, last_modified: "2026-01-01", deleted: false, error: "", path: "/app1-arm64"}

            # Component 2: mixed delete + skip -> effective skip
            {repository: "r", format: "docker", scope: "*", group: "", name: "app2", variant: "amd64", version: "1.0", component_id: "c2", decision: "delete", reason: "superseded", rank: 2, size_bytes: 200, last_modified: "2026-01-01", deleted: false, error: "", path: "/app2-amd64"}
            {repository: "r", format: "docker", scope: "*", group: "", name: "app2", variant: "arm64", version: "1.0", component_id: "c2", decision: "skip", reason: "group-unorderable", rank: null, size_bytes: 200, last_modified: "2026-01-01", deleted: false, error: "", path: "/app2-arm64"}

            # Component 3: all delete -> effective delete (executed & deleted)
            {repository: "r", format: "docker", scope: "*", group: "", name: "app3", variant: "amd64", version: "1.0", component_id: "c3", decision: "delete", reason: "superseded", rank: 2, size_bytes: 300, last_modified: "2026-01-01", deleted: true, error: "", path: "/app3-amd64"}
            {repository: "r", format: "docker", scope: "*", group: "", name: "app3", variant: "arm64", version: "1.0", component_id: "c3", decision: "delete", reason: "superseded", rank: 2, size_bytes: 300, last_modified: "2026-01-01", deleted: true, error: "", path: "/app3-arm64"}

            # Component 4: all delete -> effective delete (execution failed on one variant)
            {repository: "r", format: "docker", scope: "*", group: "", name: "app4", variant: "amd64", version: "1.0", component_id: "c4", decision: "delete", reason: "superseded", rank: 2, size_bytes: 400, last_modified: "2026-01-01", deleted: false, error: "500 Internal Server Error", path: "/app4-amd64"}
            {repository: "r", format: "docker", scope: "*", group: "", name: "app4", variant: "arm64", version: "1.0", component_id: "c4", decision: "delete", reason: "superseded", rank: 2, size_bytes: 400, last_modified: "2026-01-01", deleted: false, error: "", path: "/app4-arm64"}
        ]
        let s = (report summary $records (sample-run | merge {mode: "execute"}))
        assert equal $s.counts.components_total 4
        assert equal $s.counts.kept 1
        assert equal $s.counts.skipped 1
        assert equal $s.counts.to_delete 1 # 2 planned (c3, c4) - 1 failed (c4) = 1
        assert equal $s.counts.failed 1     # c4
        assert equal $s.counts.deleted 1    # c3
        assert equal ($s.counts.kept + $s.counts.to_delete + $s.counts.skipped + $s.counts.failed) $s.counts.components_total
        assert equal $s.bytes_reclaimable 700 # c3 (300) + c4 (400)
        assert equal $s.bytes_reclaimed 300   # c3 (300)
    } }
    { name: "summary aggregates complex multi-group and outside-pattern records correctly", run: {||
        let records = [
            # Group 1: 2 records, all keep
            {repository: "r1", format: "npm", scope: "*", group: "", name: "p1", variant: "*", version: "1.0", component_id: "p1-1", decision: "keep", reason: "within-keep-window", rank: 1, size_bytes: 10, last_modified: "2026-01-01", deleted: false, error: "", path: "/p1-1"}
            {repository: "r1", format: "npm", scope: "*", group: "", name: "p1", variant: "*", version: "2.0", component_id: "p1-2", decision: "keep", reason: "within-keep-window", rank: 2, size_bytes: 20, last_modified: "2026-01-01", deleted: false, error: "", path: "/p1-2"}

            # Group 2: 2 records, all delete
            {repository: "r1", format: "npm", scope: "*", group: "", name: "p2", variant: "*", version: "1.0", component_id: "p2-1", decision: "delete", reason: "superseded", rank: 2, size_bytes: 30, last_modified: "2026-01-01", deleted: true, error: "", path: "/p2-1"}
            {repository: "r1", format: "npm", scope: "*", group: "", name: "p2", variant: "*", version: "2.0", component_id: "p2-2", decision: "delete", reason: "superseded", rank: 3, size_bytes: 40, last_modified: "2026-01-01", deleted: true, error: "", path: "/p2-2"}

            # Group 3: 2 records, mixed keep + skip -> skipped group
            {repository: "r2", format: "yum", scope: "os", group: "x86_64", name: "k1", variant: "x86_64", version: "1.0", component_id: "k1-1", decision: "keep", reason: "within-keep-window", rank: 1, size_bytes: 50, last_modified: "2026-01-01", deleted: false, error: "", path: "/k1-1"}
            {repository: "r2", format: "yum", scope: "os", group: "x86_64", name: "k1", variant: "x86_64", version: "2.0", component_id: "k1-2", decision: "skip", reason: "group-unorderable", rank: null, size_bytes: 60, last_modified: "2026-01-01", deleted: false, error: "", path: "/k1-2"}

            # Outside-pattern records: 3 records
            {repository: "r3", format: "raw", scope: "*", group: "", name: "raw1", variant: "*", version: "", component_id: "raw-1", decision: "keep", reason: "outside-pattern", rank: null, size_bytes: 70, last_modified: "2026-01-01", deleted: false, error: "", path: "/raw-1"}
            {repository: "r3", format: "raw", scope: "*", group: "", name: "raw2", variant: "*", version: "", component_id: "raw-2", decision: "keep", reason: "outside-pattern", rank: null, size_bytes: 80, last_modified: "2026-01-01", deleted: false, error: "", path: "/raw-2"}
            {repository: "r3", format: "raw", scope: "*", group: "", name: "raw3", variant: "*", version: "", component_id: "raw-3", decision: "keep", reason: "outside-pattern", rank: null, size_bytes: 90, last_modified: "2026-01-01", deleted: false, error: "", path: "/raw-3"}
        ]
        let s = (report summary $records (sample-run | merge {mode: "execute"}))
        assert equal $s.counts.components_total 9
        assert equal $s.counts.groups_total 3
        assert equal $s.counts.groups_skipped 1
        assert equal $s.counts.kept 6
        assert equal $s.counts.to_delete 2
        assert equal $s.counts.skipped 1
        assert equal $s.counts.failed 0
        assert equal $s.counts.deleted 2
        assert equal $s.bytes_reclaimable 70
        assert equal $s.bytes_reclaimed 70
    } }
    { name: "summary scales accurately on large datasets", run: {||
        # Generate 1,000 components across 100 groups:
        # - 500 kept (size 10 each = 5000 bytes)
        # - 300 to_delete and deleted (size 20 each = 6000 bytes)
        # - 100 to_delete but failed (size 30 each = 3000 bytes)
        # - 100 skipped (size 40 each = 4000 bytes)
        # Only groups 0..9 contain skipped components (10 skipped groups).
        mut recs = []
        for i in 0..<1000 {
            let decision_type = if $i < 500 {
                "keep"
            } else if $i < 800 {
                "del_success"
            } else if $i < 900 {
                "del_fail"
            } else {
                "skip"
            }

            let group_num = if $decision_type == "skip" {
                ($i mod 10)
            } else {
                ($i mod 100)
            }

            let comp_id = $"comp-($i)"

            let rec = match $decision_type {
                "keep" => {
                    decision: "keep", reason: "within-keep-window", size_bytes: 10, deleted: false, error: ""
                }
                "del_success" => {
                    decision: "delete", reason: "superseded", size_bytes: 20, deleted: true, error: ""
                }
                "del_fail" => {
                    decision: "delete", reason: "superseded", size_bytes: 30, deleted: false, error: "HTTP 500"
                }
                "skip" => {
                    decision: "skip", reason: "group-unorderable", size_bytes: 40, deleted: false, error: ""
                }
            }

            $recs = ($recs | append {
                repository: "repo"
                format: "generic"
                scope: "scope"
                group: $"grp-($group_num)"
                name: $"pkg-($group_num)"
                variant: "*"
                version: $"1.0.($i)"
                component_id: $comp_id
                decision: $rec.decision
                reason: $rec.reason
                rank: 1
                size_bytes: $rec.size_bytes
                last_modified: "2026-01-01"
                deleted: $rec.deleted
                error: $rec.error
                path: $"/pkg-($group_num)/1.0.($i)"
            })
        }

        let s = (report summary $recs (sample-run | merge {mode: "execute"}))
        assert equal $s.counts.components_total 1000
        assert equal $s.counts.kept 500
        assert equal $s.counts.to_delete 300 # 400 planned - 100 failed = 300
        assert equal $s.counts.failed 100
        assert equal $s.counts.deleted 300
        assert equal $s.counts.skipped 100
        assert equal $s.counts.groups_total 100
        assert equal $s.counts.groups_skipped 10
        assert equal ($s.counts.kept + $s.counts.to_delete + $s.counts.skipped + $s.counts.failed) $s.counts.components_total
        assert equal $s.bytes_reclaimable 9000 # (300 * 20) + (100 * 30)
        assert equal $s.bytes_reclaimed 6000   # (300 * 20)
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
