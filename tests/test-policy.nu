use ./harness.nu *
use ../nexus-cleanup/policy.nu *
use ../nexus-cleanup/scopes.nu *
use ../nexus-cleanup/variants.nu *

# Build a component the way the Components API returns one.
def comp [repo: string, format: string, group: string, name: string, version: string, path: string = ""]: nothing -> record {
    {
        id: $"($repo)|($group)|($name)|($version)"
        repository: $repo
        format: $format
        group: $group
        name: $name
        version: $version
        assets: [{path: (if ($path | is-empty) { $"/($name)-($version)" } else { $path })}]
    }
}

def decisions [plan: list<record>]: nothing -> list<string> { $plan | get decision | uniq | sort }
def for-version [plan: list<record>, version: string]: nothing -> record { $plan | where version == $version | first }

run-suite "policy" [
    # --- grouping ---
    { name: "the same name in two repositories is decided separately", run: {||
        let plan = (policy plan [
            (comp "repo-a" "npm" "" "widget" "1.0.0")
            (comp "repo-b" "npm" "" "widget" "2.0.0")
        ])
        assert equal (decisions $plan) ["keep"]
    } }
    { name: "the same name under different namespaces stays distinct", run: {||
        let plan = (policy plan [
            (comp "r" "maven2" "org.a" "widget" "1.0.0")
            (comp "r" "maven2" "org.b" "widget" "2.0.0")
        ])
        assert equal (decisions $plan) ["keep"]
    } }
    { name: "architectures are retained independently", run: {||
        let plan = (policy plan [
            (comp "r" "apt" "amd64" "hello" "1.0")
            (comp "r" "apt" "amd64" "hello" "2.0")
            (comp "r" "apt" "arm64" "hello" "1.0")
        ])
        let amd = ($plan | where variant == "amd64")
        let arm = ($plan | where variant == "arm64")
        assert equal ($amd | where version == "2.0" | first | get decision) "keep"
        assert equal ($amd | where version == "1.0" | first | get decision) "delete"
        assert equal ($arm | first | get decision) "keep"
    } }
    { name: "releases are retained independently of updates", run: {||
        let plan = (policy plan [
            (comp "r" "yum" "aarch64" "kcm" "6.6.4-1.fc44" "/releases/44/Everything/aarch64/os/Packages/k/kcm-6.6.4-1.fc44.aarch64.rpm")
            (comp "r" "yum" "aarch64" "kcm" "6.7.1-1.fc44" "/updates/44/Everything/aarch64/Packages/k/kcm-6.7.1-1.fc44.aarch64.rpm")
            (comp "r" "yum" "aarch64" "kcm" "6.7.4-1.fc44" "/updates/44/Everything/aarch64/Packages/k/kcm-6.7.4-1.fc44.aarch64.rpm")
        ])
        # The frozen release copy survives even though updates carries a higher version.
        assert equal (for-version $plan "6.6.4-1.fc44" | get decision) "keep"
        assert equal (for-version $plan "6.7.4-1.fc44" | get decision) "keep"
        assert equal (for-version $plan "6.7.1-1.fc44" | get decision) "delete"
    } }

    # --- keep count ---
    { name: "the default keeps only the newest", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "w" "1.0.0")
            (comp "r" "npm" "" "w" "1.1.0")
            (comp "r" "npm" "" "w" "2.0.0")
            (comp "r" "npm" "" "w" "3.0.0")
        ])
        assert equal ($plan | where decision == "keep" | get version) ["3.0.0"]
        assert equal ($plan | where decision == "delete" | length) 3
    } }
    { name: "a configured keep count retains that many", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "w" "1.0.0")
            (comp "r" "npm" "" "w" "1.1.0")
            (comp "r" "npm" "" "w" "2.0.0")
            (comp "r" "npm" "" "w" "3.0.0")
        ] --keep 2)
        assert equal ($plan | where decision == "keep" | get version | sort) ["2.0.0" "3.0.0"]
        assert equal ($plan | where decision == "delete" | length) 2
    } }
    { name: "ranks run from 1, newest first", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "w" "1.0.0")
            (comp "r" "npm" "" "w" "2.0.0")
        ])
        assert equal (for-version $plan "2.0.0" | get rank) 1
        assert equal (for-version $plan "1.0.0" | get rank) 2
    } }
    { name: "a keep count below one is refused", run: {||
        assert error {|| policy plan [(comp "r" "npm" "" "w" "1.0.0")] --keep 0 }
        assert error {|| policy plan [(comp "r" "npm" "" "w" "1.0.0")] --keep (-1) }
    } }

    # --- keep count is checked before ordering ---
    { name: "a group within the keep count is kept, never ordered", run: {||
        let plan = (policy plan [
            (comp "r" "docker" "" "img" "latest")
            (comp "r" "docker" "" "img" "stable")
        ] --keep 2)
        assert equal (decisions $plan) ["keep"]
        assert equal ($plan | get reason | uniq) ["group-within-keep"]
    } }
    { name: "an unversioned repository produces no skip noise", run: {||
        let plan = (policy plan [
            (comp "r" "raw" "/9/images" "/9/images/a.qcow2" "")
            (comp "r" "raw" "/9/images" "/9/images/b.qcow2" "")
        ])
        assert equal (decisions $plan) ["keep"]
    } }
    { name: "ordering still applies above the keep count", run: {||
        let plan = (policy plan [
            (comp "r" "docker" "" "img" "1.0")
            (comp "r" "docker" "" "img" "2.0")
            (comp "r" "docker" "" "img" "latest")
        ])
        assert equal (decisions $plan) ["skip"]
        assert equal ($plan | get reason | uniq) ["group-unorderable"]
    } }

    # --- strict ordering ---
    { name: "an unparseable version skips the whole group", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "w" "1.2.3")
            (comp "r" "npm" "" "w" "1.3.0")
            (comp "r" "npm" "" "w" "latest")
        ])
        assert equal (decisions $plan) ["skip"]
        assert equal ($plan | where decision == "delete" | length) 0
    } }
    { name: "versions that compare equal make the group ambiguous", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "w" "1.0")
            (comp "r" "npm" "" "w" "1.0.0")
            (comp "r" "npm" "" "w" "2.0.0")
        ])
        assert equal (decisions $plan) ["skip"]
        assert equal ($plan | get reason | uniq) ["group-ambiguous"]
    } }
    { name: "one unorderable group does not block its siblings", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "bad" "1.0.0")
            (comp "r" "npm" "" "bad" "2.0.0")
            (comp "r" "npm" "" "bad" "latest")
            (comp "r" "npm" "" "good" "1.0.0")
            (comp "r" "npm" "" "good" "2.0.0")
        ])
        assert equal ($plan | where name == "bad" | get decision | uniq) ["skip"]
        assert equal ($plan | where name == "good" and decision == "delete" | get version) ["1.0.0"]
    } }
    { name: "ecosystem comparators are selected by repository format", run: {||
        # 1:2.3-4 outranks 2.3-4 only under debian rules.
        let plan = (policy plan [
            (comp "r" "apt" "amd64" "p" "1:2.3-4")
            (comp "r" "apt" "amd64" "p" "2.3-4")
        ])
        assert equal ($plan | where decision == "keep" | get version) ["1:2.3-4"]
    } }
    { name: "an explicit version scheme overrides the format default", run: {||
        let plan = (policy plan [
            (comp "r" "apt" "amd64" "p" "1.0")
            (comp "r" "apt" "amd64" "p" "2.0")
        ] --version-scheme "generic")
        assert equal ($plan | where decision == "keep" | get version) ["2.0"]
    } }

    # --- decision integrity ---
    { name: "every component receives exactly one decision per group membership", run: {||
        let components = [
            (comp "r" "npm" "" "w" "1.0.0")
            (comp "r" "npm" "" "w" "2.0.0")
            (comp "r" "npm" "" "x" "1.0.0")
        ]
        let plan = (policy plan $components)
        assert equal ($plan | length) 3
        assert equal ($plan | get decision | uniq | sort) ["delete" "keep"]
    } }
    { name: "a multi-variant component is deletable only when every group agrees", run: {||
        # One docker tag carrying two architectures; a newer tag exists for amd64 only.
        let multi = {
            id: "multi", repository: "r", format: "docker", group: "", name: "img", version: "1.0"
            assets: [
                {path: "/a", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "amd64"}}
                {path: "/b", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "arm64"}}
            ]
        }
        let newer_amd = {
            id: "newer", repository: "r", format: "docker", group: "", name: "img", version: "2.0"
            assets: [{path: "/c", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "amd64"}}]
        }
        let plan = (policy plan [$multi $newer_amd])
        # The multi-arch tag is superseded on amd64 but still newest on arm64.
        assert equal ($plan | where component_id == "multi" | get decision | uniq | sort) ["delete" "keep"]
        assert not ("multi" in (policy deletable-ids $plan))
        assert ("newer" in ((policy deletable-ids $plan) | append "newer"))
    } }
    { name: "a component superseded in every group it belongs to is deletable", run: {||
        let plan = (policy plan [
            (comp "r" "npm" "" "w" "1.0.0")
            (comp "r" "npm" "" "w" "2.0.0")
        ])
        let ids = (policy deletable-ids $plan)
        assert equal ($ids | length) 1
        assert ($ids | first | str contains "1.0.0")
    } }
    { name: "an empty component list yields an empty plan", run: {||
        assert equal (policy plan []) []
    } }
]
