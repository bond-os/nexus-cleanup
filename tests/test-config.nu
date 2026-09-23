use ./harness.nu *
use ../nexus-cleanup/config.nu *

def base []: nothing -> record { {url: "https://nexus.example.invalid", repositories: ["r"]} }
def resolve [extra: record = {}]: nothing -> record { config resolve ((base) | merge $extra) }

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
    { name: "credentials come from the environment", run: {||
        with-env {NEXUS_USERNAME: "u", NEXUS_PASSWORD: "p"} {
            let c = (resolve)
            assert equal $c.username "u"
            assert equal $c.password "p"
        }
    } }
]
