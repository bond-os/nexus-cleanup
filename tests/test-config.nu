use ./harness.nu *
use ../nexus-cleanup/config.nu *

def base []: nothing -> record { {url: "https://nexus.example.invalid", repositories: ["r"]} }
def resolve [extra: record = {}]: nothing -> record { config resolve ((base) | merge $extra) }

def fixture [name: string]: nothing -> string { $"($env.FILE_PWD)/fixtures/config/($name)" }

# Resolve flags over a configuration fixture, with the connection environment cleared.
def layered [name: string, flags: record = {}]: nothing -> record {
    with-env {NEXUS_URL: "https://nexus.example.invalid", NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
        config resolve $flags --file (config load (fixture $name))
    }
}

def layered-error [name: string, flags: record = {}]: nothing -> any {
    try { layered $name $flags; null } catch {|e| $e }
}

run-suite "config: file layering" [
    { name: "a flag overrides the file", run: {||
        assert equal (layered "settings.yaml" {keep: 5} | get keep) 5
    } }
    { name: "the file overrides the defaults", run: {||
        let c = (layered "settings.yaml")
        assert equal $c.keep 3
        assert equal $c.format "csv"
        assert equal $c.timeout 2min
    } }
    { name: "a null flag counts as not given", run: {||
        assert equal (layered "settings.yaml" {keep: null, format: null} | get keep) 3
    } }
    { name: "NEXUS_URL overrides the file's url, and a URL flag overrides both", run: {||
        let loaded = (config load (fixture "connection.yaml"))
        with-env {NEXUS_URL: "https://from-env.invalid", NEXUS_USERNAME: "env-user"} {
            let c = (config resolve {} --file $loaded)
            assert equal $c.url "https://from-env.invalid"
            assert equal $c.username "env-user"
            assert equal (config resolve {url: "https://from-flag.invalid"} --file $loaded | get url) "https://from-flag.invalid"
        }
    } }
    { name: "the file's url and username apply when nothing overrides them", run: {||
        with-env {NEXUS_URL: "", NEXUS_USERNAME: ""} {
            let c = (config resolve {} --file (config load (fixture "connection.yaml")))
            assert equal $c.url "https://from-file.invalid"
            assert equal $c.username "file-user"
        }
    } }
    { name: "fail-on-skip is on when either the flag or the file sets it", run: {||
        assert equal (layered "settings.yaml" {fail_on_skip: false} | get fail_on_skip) true
        assert equal (layered "connection.yaml" {fail_on_skip: true} | get fail_on_skip) true
        assert equal (layered "connection.yaml" {fail_on_skip: false} | get fail_on_skip) false
    } }
    { name: "allow-hosted is on when either the flag or the file sets it", run: {||
        assert equal (layered "allow-hosted.yaml" {allow_hosted: false} | get allow_hosted) true
        assert equal (layered "connection.yaml" {allow_hosted: true} | get allow_hosted) true
        assert equal (layered "connection.yaml" {allow_hosted: false} | get allow_hosted) false
    } }
    { name: "allow-hosted never makes a run execute", run: {||
        assert equal (layered "allow-hosted.yaml" | get execute) false
        assert equal (layered "connection.yaml" {allow_hosted: true} | get execute) false
    } }
    { name: "names on the command line replace a file pattern", run: {||
        let c = (layered "pattern-only.yaml" {repositories: ["npm-proxy"]})
        assert equal $c.repositories ["npm-proxy"]
        assert equal $c.pattern ""
    } }
    { name: "a pattern on the command line replaces the file's names", run: {||
        let c = (layered "connection.yaml" {pattern: "yum-*"})
        assert equal $c.repositories []
        assert equal $c.pattern "yum-*"
    } }
    { name: "the file's selection applies when the command line has none", run: {||
        let c = (layered "connection.yaml" {repositories: [], pattern: ""})
        assert equal $c.repositories ["a" "b"]
    } }
    { name: "no selection anywhere is the usual usage error", run: {||
        let err = (layered-error "settings-without-selection.yaml")
        assert ($err.msg | str contains "name at least one repository")
    } }
    { name: "an invalid file value names the key and the file", run: {||
        let err = (layered-error "keep-zero.yaml")
        assert ($err.msg | str contains "'keep' in")
        assert ($err.msg | str contains "keep-zero.yaml")
        assert not ($err.msg | str contains "--keep")
    } }
    { name: "a path pattern without its version group in the file names the key and the file", run: {||
        let err = (layered-error "from-path-without-version.yaml")
        assert ($err.msg | str contains "'from-path' in")
        assert ($err.msg | str contains "from-path-without-version.yaml")
    } }
    { name: "the same values as flags still name the flags", run: {||
        assert ((try { resolve {keep: 0}; null } catch {|e| $e }).msg | str contains "--keep")
        let p = '^/(?P<name>[^/]+)/'
        assert ((try { resolve {from_path: $p}; null } catch {|e| $e }).msg | str contains "--from-path")
    } }
    { name: "the resolved configuration names its file, or none", run: {||
        assert equal (layered "settings.yaml" | get config_file) (fixture "settings.yaml")
        assert equal (resolve | get config_file) ""
    } }
    { name: "--require-cap refuses a run with no cap from any source, dry or executing", run: {||
        for execute in [false true] {
            let err = (layered-error "settings.yaml" {require_cap: true, execute: $execute})
            assert ($err.msg | str contains "--max-deletions")
            assert ($err.msg | str contains "--max-deletion-share")
        }
    } }
    { name: "a cap from the file or a flag satisfies --require-cap", run: {||
        assert equal (layered "capped.yaml" {require_cap: true} | get max_deletions) 200
        assert equal (layered "settings.yaml" {require_cap: true, max_deletion_share: 0.2} | get max_deletion_share) 0.2
    } }
    { name: "--require-cap never makes a run execute", run: {||
        assert equal (layered "capped.yaml" {require_cap: true} | get execute) false
    } }
    { name: "require-cap is not a file setting", run: {||
        let err = (try { config load (fixture "require-cap.yaml"); null } catch {|e| $e })
        assert ($err.msg | str contains "unknown key 'require-cap'")
    } }
    { name: "a file never makes a run execute", run: {||
        assert equal (layered "full.yaml" | get execute) false
    } }
]

run-suite "config" [
    { name: "a flag overrides the environment", run: {||
        with-env {NEXUS_URL: "https://from-env.invalid"} {
            assert equal (resolve {url: "https://from-flag.invalid"} | get url) "https://from-flag.invalid"
        }
    } }
    { name: "the environment is used when no flag is given", run: {||
        with-env {NEXUS_URL: "https://from-env.invalid"} {
            assert equal (config resolve {repositories: ["r"]} | get url) "https://from-env.invalid"
        }
    } }
    { name: "a missing URL is a usage error", run: {||
        with-env {NEXUS_URL: ""} {
            let err = (try { config resolve {repositories: ["r"]}; null } catch {|e| $e })
            assert not equal $err null
            assert ($err.msg | str contains "NEXUS_URL")
        }
    } }
    { name: "a trailing slash on the URL is normalised away", run: {||
        assert equal (resolve {url: "https://n.invalid/"} | get url) "https://n.invalid"
    } }
    { name: "a non-positive keep count is refused", run: {||
        for k in [0 (-1)] {
            let err = (try { resolve {keep: $k}; null } catch {|e| $e })
            assert ($err.msg | str contains "--keep")
        }
    } }
    { name: "a non-positive timeout is refused", run: {||
        let err = (try { resolve {timeout: 0sec}; null } catch {|e| $e })
        assert ($err.msg | str contains "--timeout")
    } }
    { name: "a retry limit below one is refused", run: {||
        let err = (try { resolve {max_attempts: 0}; null } catch {|e| $e })
        assert ($err.msg | str contains "--max-attempts")
    } }
    { name: "an unknown output format is refused", run: {||
        let err = (try { resolve {format: "yaml"}; null } catch {|e| $e })
        assert ($err.msg | str contains "--format")
    } }
    { name: "an unknown version scheme is refused", run: {||
        let err = (try { resolve {version_scheme: "semver"}; null } catch {|e| $e })
        assert ($err.msg | str contains "--version-scheme")
    } }
    { name: "a scope pattern without a scope group is refused", run: {||
        let err = (try { resolve {scope_pattern: '^/(releases/[0-9]+)'}; null } catch {|e| $e })
        assert ($err.msg | str contains "--scope-from-path")
    } }
    { name: "an uncompilable scope pattern is refused", run: {||
        let err = (try { resolve {scope_pattern: '^/(?P<scope>[unclosed'}; null } catch {|e| $e })
        assert ($err.msg | str contains "--scope-from-path")
    } }
    { name: "a valid scope pattern is accepted", run: {||
        assert equal (resolve {scope_pattern: '^/(?P<scope>[^/]+)'} | get scope_pattern) '^/(?P<scope>[^/]+)'
    } }
    { name: "a path pattern missing the name group is refused", run: {||
        let err = (try { resolve {from_path: '^/(?P<version>[0-9]{8})/'}; null } catch {|e| $e })
        assert ($err.msg | str contains "--from-path")
    } }
    { name: "a path pattern missing the version group is refused", run: {||
        let err = (try { resolve {from_path: '^/(?P<name>[^/]+)/'}; null } catch {|e| $e })
        assert ($err.msg | str contains "--from-path")
    } }
    { name: "an uncompilable path pattern is refused", run: {||
        let err = (try { resolve {from_path: '^/(?P<name>[^/]+)/(?P<version>[unclosed'}; null } catch {|e| $e })
        assert ($err.msg | str contains "--from-path")
    } }
    { name: "a valid path pattern is accepted", run: {||
        let p = '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'
        assert equal (resolve {from_path: $p} | get from_path) $p
    } }
    { name: "the date version scheme is accepted", run: {||
        assert equal (resolve {version_scheme: "date"} | get version_scheme) "date"
    } }
    { name: "no path pattern is the default", run: {||
        assert equal (resolve | get from_path) ""
    } }
    { name: "no repository selection is a usage error", run: {||
        let err = (try { config resolve {url: "https://n.invalid"}; null } catch {|e| $e })
        assert not equal $err null
        assert ($err.msg | str contains "repository")
    } }
    { name: "a pattern alone is a valid selection", run: {||
        assert equal (config resolve {url: "https://n.invalid", pattern: "yum-*"} | get pattern) "yum-*"
    } }
    { name: "a negative deletion cap is refused", run: {||
        let err = (try { resolve {max_deletions: -1}; null } catch {|e| $e })
        assert ($err.msg | str contains "--max-deletions")
    } }
    { name: "a deletion share outside 0..1 is refused", run: {||
        for v in [-0.5 1.5] {
            let err = (try { resolve {max_deletion_share: $v}; null } catch {|e| $e })
            assert ($err.msg | str contains "--max-deletion-share")
        }
    } }
    { name: "dry run is the resolved default", run: {||
        assert equal (resolve | get execute) false
        assert equal (resolve | get fail_on_skip) false
    } }
    { name: "hosted repositories are not allowed by default", run: {||
        assert equal (resolve | get allow_hosted) false
        assert equal (resolve {allow_hosted: true} | get allow_hosted) true
    } }
    { name: "credentials come from the environment", run: {||
        with-env {NEXUS_USERNAME: "u", NEXUS_PASSWORD: "p"} {
            let c = (resolve)
            assert equal $c.username "u"
            assert equal $c.password "p"
        }
    } }
]
