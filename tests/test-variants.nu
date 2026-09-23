use ./harness.nu *
use ../nexus-cleanup/variants.nu *

def fixture [path: string]: nothing -> list<record> {
    open $"($env.FILE_PWD)/fixtures/($path)" | get items
}

def find-component [items: list<record>, name: string, version: string]: nothing -> record {
    $items | where name == $name and version == $version | first
}

run-suite "variants" [
    # --- architecture from a format-specific asset attribute (docker) ---
    { name: "docker architecture is read from the asset attribute", run: {||
        let c = {
            format: "docker"
            group: ""
            name: "library/redis"
            version: "latest"
            assets: [{
                path: "/v2/library/redis/manifests/latest"
                contentType: "application/vnd.docker.distribution.manifest.v2+json"
                docker: {architecture: "arm64", os: "linux"}
            }]
        }
        assert equal (variant of $c) ["arm64"]
    } }
    { name: "a docker manifest list yields the all-architectures variant", run: {||
        let c = {
            format: "docker"
            group: ""
            name: "library/caddy"
            version: "2.5.2-alpine"
            assets: [{
                path: "/v2/library/caddy/manifests/2.5.2-alpine"
                contentType: "application/vnd.docker.distribution.manifest.list.v2+json"
                docker: {}
            }]
        }
        assert equal (variant of $c) [$MULTIARCH_VARIANT]
    } }
    { name: "an OCI image index yields the all-architectures variant", run: {||
        let c = {
            format: "docker"
            group: ""
            name: "ubuntu/python"
            version: "3.12-24.04"
            assets: [{
                path: "/v2/ubuntu/python/manifests/3.12-24.04"
                contentType: "application/vnd.oci.image.index.v1+json"
                docker: {}
            }]
        }
        assert equal (variant of $c) [$MULTIARCH_VARIANT]
    } }
    { name: "the all-architectures variant is distinct from the implicit one", run: {||
        assert not equal $MULTIARCH_VARIANT $IMPLICIT_VARIANT
    } }

    # --- architecture from the component group (apt, yum) ---
    { name: "apt architecture is read from the component group", run: {||
        let items = (fixture "apt/apt-proxy-deb.debian.org-page-0.json")
        let c = (find-component $items "hello" "2.10-2")
        assert equal (variant of $c) [$c.group]
        assert ($c.group in ["amd64" "arm64"])
    } }
    { name: "every recorded apt component resolves to a named architecture", run: {||
        let items = (fixture "apt/apt-proxy-deb.debian.org-page-0.json")
        let variants = ($items | each {|c| variant of $c } | flatten | uniq | sort)
        assert equal $variants ["amd64" "arm64"]
    } }
    { name: "yum architecture is read from the component group", run: {||
        let items = (fixture "yum/yum-proxy-resources.ovirt.org-page-0.json")
        let c = ($items | first)
        assert equal (variant of $c) ["noarch"]
    } }

    # --- filename fallback when the attribute source is absent ---
    { name: "a deb filename yields the architecture when the group is gone", run: {||
        let items = (fixture "apt/apt-proxy-deb.debian.org-page-0.json")
        let c = (find-component $items "hello" "2.10-3")
        let expected = (variant of $c)
        let stripped = ($c | update group "")
        assert equal (variant of $stripped) $expected
    } }
    { name: "an rpm filename yields the architecture when the group is gone", run: {||
        let items = (fixture "yum/yum-proxy-resources.ovirt.org-page-0.json")
        let c = ($items | first)
        let stripped = ($c | update group "")
        assert equal (variant of $stripped) ["noarch"]
    } }
    { name: "a synthetic x86_64 rpm path parses", run: {||
        let c = {
            format: "yum"
            group: ""
            name: "pkg"
            version: "1.2.3-1.el9"
            assets: [{path: "/9/os/x86_64/Packages/p/pkg-1.2.3-1.el9.x86_64.rpm", contentType: "application/x-rpm"}]
        }
        assert equal (variant of $c) ["x86_64"]
    } }

    # --- formats with no architecture dimension ---
    { name: "formats with no architecture dimension yield the implicit variant", run: {||
        for f in [
            ["npm/npm-proxy-npm-page-0.json"]
            ["pypi/pypi-proxy-page-0.json"]
            ["nuget/nuget.org-proxy-page-0.json"]
            ["helm/helm-jenkins-page-0.json"]
            ["huggingface/proxy-hg-page-0.json"]
            ["raw/raw-proxy-repo.almalinux.org-page-0.json"]
            ["conan/conan-proxy-conan.io-page-0.json"]
        ] {
            let items = (fixture ($f | first))
            let c = ($items | first)
            assert equal (variant of $c) [$IMPLICIT_VARIANT]
        }
    } }
    { name: "a raw path that merely contains x86_64 is not an architecture", run: {||
        # The AlmaLinux qcow2 lives under /9/cloud/x86_64/images/ but raw has no
        # architecture dimension; guessing here would split groups on a directory name.
        let items = (fixture "raw/raw-proxy-repo.almalinux.org-page-0.json")
        assert equal (variant of ($items | first)) [$IMPLICIT_VARIANT]
    } }

    # --- multi-architecture components ---
    { name: "a component carrying two architectures yields both", run: {||
        let c = {
            format: "docker"
            group: ""
            name: "library/multi"
            version: "1.0"
            assets: [
                {path: "/a", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "amd64"}}
                {path: "/b", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "arm64"}}
            ]
        }
        assert equal (variant of $c | sort) ["amd64" "arm64"]
    } }
    { name: "duplicate architectures across assets collapse to one variant", run: {||
        let c = {
            format: "docker"
            group: ""
            name: "library/dup"
            version: "1.0"
            assets: [
                {path: "/a", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "amd64"}}
                {path: "/b", contentType: "application/vnd.docker.distribution.manifest.v2+json", docker: {architecture: "amd64"}}
            ]
        }
        assert equal (variant of $c) ["amd64"]
    } }

    # --- robustness ---
    { name: "a component with no assets still resolves to a variant", run: {||
        let c = {format: "npm", group: "", name: "x", version: "1.0", assets: []}
        assert equal (variant of $c) [$IMPLICIT_VARIANT]
    } }
    { name: "a missing attribute map is tolerated", run: {||
        let c = {
            format: "docker"
            group: ""
            name: "library/bare"
            version: "1.0"
            assets: [{path: "/a", contentType: "application/vnd.docker.distribution.manifest.v2+json"}]
        }
        assert equal (variant of $c) [$IMPLICIT_VARIANT]
    } }
    { name: "an unknown format resolves to the implicit variant", run: {||
        let c = {format: "some-future-format", group: "whatever", name: "x", version: "1.0", assets: [{path: "/x_amd64.deb"}]}
        assert equal (variant of $c) [$IMPLICIT_VARIANT]
    } }
]
