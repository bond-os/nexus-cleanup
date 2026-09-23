use ./harness.nu *
use ../nexus-cleanup/policy.nu *

const PATTERN = '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'

def layout []: nothing -> list<record> {
    open $"($env.FILE_PWD)/fixtures/raw/path-derived-layout.json" | get items
}

def plan-layout [--keep: int = 14]: nothing -> list<record> {
    policy plan (layout) --from-path $PATTERN --version-scheme date --keep $keep
}

def raw [path: string]: nothing -> record {
    {id: $path, repository: "r", format: "raw", group: ($path | path dirname), name: $path, version: "", assets: [{path: $path, fileSize: 1}]}
}

def dirs-with [plan: list<record>, parent: string, decision: string]: nothing -> list<string> {
    $plan | where name == $parent and decision == $decision | get version | uniq | sort
}

run-suite "policy: path-derived" [
    # --- the motivating case ---
    { name: "each parent keeps exactly its 14 newest date directories", run: {||
        let plan = (plan-layout)
        assert equal (dirs-with $plan "some_dir" "keep" | length) 14
        assert equal (dirs-with $plan "some_other_dir" "keep" | length) 14
    } }
    { name: "the 2 oldest directories per parent are marked for deletion, all their files", run: {||
        let plan = (plan-layout)
        assert equal (dirs-with $plan "some_dir" "delete") ["20250101" "20250102"]
        assert equal (dirs-with $plan "some_other_dir" "delete") ["20240601" "20240602"]
        assert equal ($plan | where decision == "delete" | length) 12
    } }
    { name: "semver-like and top-level files are kept as outside the pattern", run: {||
        let plan = (plan-layout)
        let outside = ($plan | where reason == "outside-pattern")
        assert equal ($outside | length) 8
        assert equal ($outside | get decision | uniq) ["keep"]
        for p in ["3.2.4.24-something" "3.2.5" "12345678.0.1" "app-at-top-level"] {
            assert equal ($outside | where {|r| $r.component_id | str contains $p } | length) 2
        }
    } }
    { name: "no outside-pattern component is ever deletable", run: {||
        let plan = (plan-layout --keep 1)
        let deletable = (policy deletable-ids $plan)
        for r in ($plan | where reason == "outside-pattern") {
            assert not ($r.component_id in $deletable)
        }
    } }
    { name: "outside-pattern components do not count towards the keep count", run: {||
        # 16 date directories plus 4 unmatched locations: if the unmatched ones
        # counted, fewer than 2 directories would be deleted.
        assert equal (dirs-with (plan-layout) "some_dir" "delete" | length) 2
    } }
    { name: "the two parents are decided independently", run: {||
        let plan = (plan-layout)
        assert not ("20240601" in (dirs-with $plan "some_dir" "delete"))
        assert not ("20250101" in (dirs-with $plan "some_other_dir" "delete"))
    } }
    { name: "files of one directory share one rank and one decision", run: {||
        let rows = (plan-layout | where name == "some_dir" and version == "20250102")
        assert equal ($rows | length) 3
        assert equal ($rows | get rank | uniq | length) 1
        assert equal ($rows | get decision | uniq) ["delete"]
    } }
    { name: "a same-day respin ranks between its date and the next day", run: {||
        let plan = (plan-layout)
        let rank = {|v| $plan | where name == "some_dir" and version == $v | first | get rank }
        assert greater (do $rank "20250103") (do $rank "20250103-hotfix")
        assert greater (do $rank "20250103-hotfix") (do $rank "20250104")
    } }
    { name: "path-derived records carry the extracted name and version", run: {||
        let r = (plan-layout | where component_id == "raw-dates:/some_dir/20250105/app.tar.gz" | first)
        assert equal $r.name "some_dir"
        assert equal $r.version "20250105"
        assert equal $r.group ""
    } }

    # --- keep count measured in directories ---
    { name: "10 directories of 30 files at keep 14 are all kept without ordering", run: {||
        let comps = (1..10 | each {|d| ["a" "b" "c"] | each {|f| raw $"/some_dir/202501($d | fill --alignment right --character '0' --width 2)/($f)" } } | flatten)
        let plan = (policy plan $comps --from-path $PATTERN --version-scheme date --keep 14)
        assert equal ($plan | length) 30
        assert equal ($plan | get reason | uniq) ["group-within-keep"]
    } }
    { name: "an invalid calendar date above the keep count skips the whole group", run: {||
        let comps = [
            (raw "/some_dir/20250101/a") (raw "/some_dir/20250102/a")
            (raw "/some_dir/20250229/a")
        ]
        let plan = (policy plan $comps --from-path $PATTERN --version-scheme date --keep 1)
        assert equal ($plan | get decision | uniq) ["skip"]
        assert equal ($plan | get reason | uniq) ["group-unorderable"]
    } }
    { name: "distinct version strings that compare equal are still ambiguous", run: {||
        let pattern = '^/(?P<name>some_dir)/(?P<version>[^/]+)/'
        let comps = [(raw "/some_dir/1.0/a") (raw "/some_dir/1.0.0/a") (raw "/some_dir/2.0/a")]
        let plan = (policy plan $comps --from-path $pattern --keep 1)
        assert equal ($plan | get reason | uniq) ["group-ambiguous"]
    } }
    { name: "many files sharing a version are not ambiguous", run: {||
        let pattern = '^/(?P<name>some_dir)/(?P<version>[^/]+)/'
        let comps = [(raw "/some_dir/1.0/a") (raw "/some_dir/1.0/b") (raw "/some_dir/2.0/a")]
        let plan = (policy plan $comps --from-path $pattern --keep 1)
        assert equal ($plan | where version == "1.0" | get decision | uniq) ["delete"]
        assert equal ($plan | where version == "2.0" | get decision | uniq) ["keep"]
    } }

    # --- the pattern applies to any format ---
    { name: "a pattern groups and versions non-raw components the same way", run: {||
        let pattern = '^/(?P<name>builds)/(?P<version>[0-9]{8})/'
        let comps = [
            {id: "n1", repository: "r", format: "npm", group: "", name: "x", version: "9.9.9", assets: [{path: "/builds/20250101/x.tgz"}]}
            {id: "n2", repository: "r", format: "npm", group: "", name: "y", version: "1.0.0", assets: [{path: "/builds/20250102/y.tgz"}]}
        ]
        let plan = (policy plan $comps --from-path $pattern --version-scheme date)
        assert equal ($plan | where component_id == "n1" | first | get decision) "delete"
        assert equal ($plan | where component_id == "n2" | first | get decision) "keep"
    } }

    # --- no pattern, no change ---
    { name: "without a pattern no record carries the outside-pattern reason", run: {||
        let plan = (policy plan (layout))
        assert equal ($plan | where reason == "outside-pattern" | length) 0
        assert equal ($plan | get decision | uniq) ["keep"]
    } }
    { name: "outside-pattern is part of the closed reason set", run: {||
        assert ("outside-pattern" in $REASONS)
    } }
]
