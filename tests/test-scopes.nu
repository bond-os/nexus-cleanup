use ./harness.nu *
use ../nexus-cleanup/scopes.nu *

def fixture [path: string]: nothing -> list<record> {
    open $"($env.FILE_PWD)/fixtures/($path)" | get items
}

run-suite "scopes" [
    # --- yum: the release tree and the updates tree must not compete ---
    { name: "a release tree and an updates tree yield different scopes", run: {||
        let release = {format: "yum", assets: [{path: "/releases/44/Everything/aarch64/os/Packages/k/kcm-plasmalogin-6.6.4-1.fc44.aarch64.rpm"}]}
        let updates = {format: "yum", assets: [{path: "/updates/44/Everything/aarch64/Packages/k/kcm-plasmalogin-6.7.4-1.fc44.aarch64.rpm"}]}
        assert not equal (scope of $release) (scope of $updates)
    } }
    { name: "two versions in the same tree share a scope", run: {||
        let a = {format: "yum", assets: [{path: "/updates/44/Everything/aarch64/Packages/k/kcm-plasmalogin-6.7.1-1.fc44.aarch64.rpm"}]}
        let b = {format: "yum", assets: [{path: "/updates/44/Everything/aarch64/Packages/k/kcm-plasmalogin-6.7.4-1.fc44.aarch64.rpm"}]}
        assert equal (scope of $a) (scope of $b)
    } }
    { name: "two distribution versions yield different scopes", run: {||
        let el8 = {format: "yum", assets: [{path: "/pub/epel/8/Everything/x86_64/Packages/p/python3-webob-1.8.8-2.el8.noarch.rpm"}]}
        let el9 = {format: "yum", assets: [{path: "/pub/epel/9/Everything/x86_64/Packages/p/python3-webob-1.8.11-1.el9.noarch.rpm"}]}
        assert not equal (scope of $el8) (scope of $el9)
    } }
    { name: "recorded yum components scope by their directory", run: {||
        let c = (fixture "yum/yum-proxy-resources.ovirt.org-page-0.json" | first)
        assert equal (scope of $c) ($c.assets.0.path | path dirname)
        assert not equal (scope of $c) $IMPLICIT_SCOPE
    } }

    # --- apt: the suite comes from the repository's own configuration ---
    { name: "apt scope is the repository's declared distribution", run: {||
        let c = (fixture "apt/apt-proxy-deb.debian.org-page-0.json" | first)
        assert equal (scope of $c {distribution: "bookworm"}) "bookworm"
    } }
    { name: "apt without a declared distribution falls back to the implicit scope", run: {||
        let c = (fixture "apt/apt-proxy-deb.debian.org-page-0.json" | first)
        assert equal (scope of $c) $IMPLICIT_SCOPE
        assert equal (scope of $c {distribution: ""}) $IMPLICIT_SCOPE
    } }
    { name: "apt scope ignores the pool path, which encodes no suite", run: {||
        let a = {format: "apt", assets: [{path: "/pool/main/h/hello/hello_2.10-3_amd64.deb"}]}
        let b = {format: "apt", assets: [{path: "/pool/main/h/hello/hello_2.10-5_amd64.deb"}]}
        assert equal (scope of $a {distribution: "bookworm"}) (scope of $b {distribution: "bookworm"})
    } }

    # --- formats with no reliable signal ---
    { name: "formats with no scope signal share one implicit scope", run: {||
        for f in [
            ["npm/npm-proxy-npm-page-0.json"]
            ["pypi/pypi-proxy-page-0.json"]
            ["nuget/nuget.org-proxy-page-0.json"]
            ["docker/docker-proxy-hub-page-0.json"]
            ["helm/helm-jenkins-page-0.json"]
            ["raw/raw-proxy-repo.almalinux.org-page-0.json"]
        ] {
            let c = (fixture ($f | first) | first)
            assert equal (scope of $c) $IMPLICIT_SCOPE
        }
    } }
    { name: "a version-bearing maven directory is never used as a scope", run: {||
        # Scoping by directory here would put every version in its own group and
        # silently retain everything.
        let v1 = {format: "maven2", assets: [{path: "/org/example/widget/1.2.3/widget-1.2.3.jar"}]}
        let v2 = {format: "maven2", assets: [{path: "/org/example/widget/2.0.0/widget-2.0.0.jar"}]}
        assert equal (scope of $v1) $IMPLICIT_SCOPE
        assert equal (scope of $v1) (scope of $v2)
    } }

    # --- caller-supplied pattern ---
    { name: "a supplied pattern overrides the format default", run: {||
        let c = {format: "yum", assets: [{path: "/releases/44/Everything/aarch64/os/Packages/k/x.rpm"}]}
        assert equal (scope of $c --pattern '^/(?P<scope>[^/]+/[0-9]+)') "releases/44"
    } }
    { name: "a supplied pattern applies to formats that have no default", run: {||
        let c = {format: "npm", assets: [{path: "/scoped/pkg/-/pkg-1.0.0.tgz"}]}
        assert equal (scope of $c --pattern '^/(?P<scope>[^/]+)') "scoped"
    } }
    { name: "a path that does not match the pattern falls back to the implicit scope", run: {||
        let c = {format: "yum", assets: [{path: "/odd/layout/x.rpm"}]}
        assert equal (scope of $c --pattern '^/(?P<scope>releases/[0-9]+)') $IMPLICIT_SCOPE
    } }

    # --- robustness ---
    { name: "a component with no assets yields the implicit scope", run: {||
        assert equal (scope of {format: "yum", assets: []}) $IMPLICIT_SCOPE
        assert equal (scope of {format: "yum"}) $IMPLICIT_SCOPE
    } }
    { name: "an unknown format yields the implicit scope", run: {||
        let c = {format: "some-future-format", assets: [{path: "/a/b/c.bin"}]}
        assert equal (scope of $c) $IMPLICIT_SCOPE
    } }
]
