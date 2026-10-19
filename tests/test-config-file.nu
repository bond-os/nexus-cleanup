use ./harness.nu *
use ../nexus-cleanup/config.nu *
use ../nexus-cleanup/version.nu [VERSION]

def fixture [name: string]: nothing -> string { $"($env.FILE_PWD)/fixtures/config/($name)" }

# The error raised by loading a fixture, or null when it loads.
def load-error [name: string]: nothing -> any {
    try { config load (fixture $name); null } catch {|e| $e }
}

def assert-refused [name: string, ...needles: string] {
    let err = (load-error $name)
    assert not equal $err null $"($name) was accepted"
    assert ($err.msg | str starts-with "usage:") $"not a usage error: ($err.msg)"
    for n in $needles {
        assert ($err.msg | str contains $n) $"'($n)' missing from: ($err.msg)"
    }
}

run-suite "config file" [
    { name: "every recognised key maps to its setting with the right type", run: {||
        let loaded = (config load (fixture "full.yaml"))
        assert equal $loaded.path (fixture "full.yaml")
        let v = $loaded.values
        assert equal $v.url "https://nexus.example.invalid"
        assert equal $v.username "cleanup-bot"
        assert equal $v.repositories ["yum-proxy-a" "yum-proxy-b"]
        assert equal $v.pattern "yum-proxy-*"
        assert equal $v.keep 3
        assert equal $v.timeout 2min
        assert equal $v.max_attempts 5
        assert equal $v.format "csv"
        assert equal $v.version_scheme "rpm"
        assert equal $v.scope_pattern '^/(?P<scope>[^/]+)/'
        assert equal $v.from_path '^/(?P<name>app)/(?P<version>[0-9]{8})/'
        assert equal $v.fail_on_skip true
        assert equal $v.max_deletions 200
        assert equal $v.max_deletion_share 0.5
        assert equal $v.summary_out "summary.json"
    } }
    { name: "the schema reference is accepted and ignored", run: {||
        assert not ("$schema" in ((config load (fixture "full.yaml")).values | columns))
    } }
    { name: "a schema reference that is not text is refused", run: {||
        assert-refused "schema-not-text.yaml" "$schema" "schema-not-text.yaml"
    } }
    { name: "a timeout is read as a duration", run: {||
        assert equal ((config load (fixture "settings.yaml")).values.timeout) 2min
    } }
    { name: "a whole-number deletion share becomes a float", run: {||
        let share = ((config load (fixture "share-whole-number.yaml")).values.max_deletion_share)
        assert equal $share 1.0
        assert equal ($share | describe) "float"
    } }
    { name: "an empty file yields no settings", run: {||
        assert equal ((config load (fixture "empty.yaml")).values) {}
        assert equal ((config load (fixture "comment-only.yaml")).values) {}
    } }
    { name: "a missing file is refused, naming the path", run: {||
        let err = (try { config load (fixture "absent.yaml"); null } catch {|e| $e })
        assert ($err.msg | str starts-with "usage:")
        assert ($err.msg | str contains "absent.yaml")
    } }
    { name: "a document that is not YAML is refused, naming the path", run: {||
        assert-refused "invalid.yaml" "invalid.yaml"
    } }
    { name: "a top-level sequence is refused as not a mapping", run: {||
        assert-refused "sequence.yaml" "sequence.yaml" "mapping"
    } }
    { name: "a misspelt key is refused, naming the key and the path", run: {||
        assert-refused "misspelt-key.yaml" "keeep" "misspelt-key.yaml"
    } }
    { name: "a keep count given as text is refused, naming the key", run: {||
        assert-refused "keep-as-text.yaml" "keep" "keep-as-text.yaml"
    } }
    { name: "a switch given as text is refused, naming the key", run: {||
        assert-refused "switch-as-text.yaml" "fail-on-skip" "switch-as-text.yaml"
    } }
    { name: "execute is refused whatever its value, pointing at the flag", run: {||
        assert-refused "execute-true.yaml" "execute" "--execute"
        assert-refused "execute-false.yaml" "execute" "--execute"
    } }
    { name: "a password is refused without echoing it", run: {||
        assert-refused "password.yaml" "password" "NEXUS_PASSWORD"
        assert not ((load-error "password.yaml").msg | str contains "s3cret")
    } }
    { name: "credentials embedded in the URL are refused without echoing them", run: {||
        assert-refused "url-with-credentials.yaml" "url" "NEXUS_PASSWORD"
        assert not ((load-error "url-with-credentials.yaml").msg | str contains "s3cret")
    } }
    { name: "a refused key is reported before an unknown one", run: {||
        let err = (load-error "execute-and-unknown.yaml")
        assert ($err.msg | str contains "--execute")
        assert not ($err.msg | str contains "keeep")
    } }

    # --- the shipped example files ---
    { name: "every example configuration file is accepted, with a cap, by the tool", run: {||
        let files = (glob $"($env.FILE_PWD | path dirname)/examples/configs/*.yaml")
        assert greater ($files | length) 1
        for f in $files {
            with-env {NEXUS_URL: "https://nexus.example.invalid"} {
                config resolve {require_cap: true} --file (config load $f)
            }
        }
    } }
    { name: "every example pins the schema to this release inside release-please markers", run: {||
        let url = $"https://raw.githubusercontent.com/bond-os/nexus-cleanup/v($VERSION)/schema/config.schema.json"
        for f in (glob $"($env.FILE_PWD | path dirname)/examples/configs/*.yaml") {
            let head = (open --raw $f | lines | first 3)
            assert equal $head [
                "# x-release-please-start-version"
                $"# yaml-language-server: $schema=($url)"
                "# x-release-please-end"
            ] ($f | path basename)
        }
    } }

    # --- YAML coercions (task 1.3): the intended type, or refused; never another valid setting ---
    { name: "a bare yes for a switch is refused rather than read as true", run: {||
        assert-refused "switch-as-bare-yes.yaml" "fail-on-skip"
    } }
    { name: "a keep count with a leading zero is read in decimal", run: {||
        assert equal ((config load (fixture "keep-leading-zero.yaml")).values.keep) 10
    } }
    { name: "a bare no for the version scheme stays the text 'no', which validation refuses", run: {||
        let loaded = (config load (fixture "scheme-as-bare-no.yaml"))
        assert equal $loaded.values.version_scheme "no"
        let err = (try {
            config resolve {url: "https://n.invalid"} --file $loaded; null
        } catch {|e| $e })
        assert ($err.msg | str contains "version-scheme")
    } }
]

def readme []: nothing -> string { open --raw $"($env.FILE_PWD | path dirname)/README.md" }

run-suite "config file: documentation" [
    { name: "the README's key table lists exactly the recognised keys", run: {||
        let table = (readme | split row "<!-- config-keys:start -->" | get 1 | split row "<!-- config-keys:end -->" | get 0)
        let keys = ($table | parse --regex '(?m)^\| `(?P<k>[^`]+)` \|' | get k)
        assert equal $keys ($CONFIG_KEYS | get key)
    } }
    { name: "the README's worked file is the raw example, without its comments", run: {||
        let block = (readme | split row "## Configuration files" | get 1 | split row "```yaml\n" | get 1 | split row "```" | get 0)
        let settings = {|text: string| $text | lines | where {|l| not ($l | str starts-with "#") and ($l | is-not-empty) } }
        let example = (open --raw $"($env.FILE_PWD | path dirname)/examples/configs/raw-builds.yaml")
        assert equal (do $settings $block) (do $settings $example)
        assert equal ($block | lines | first 3) ($example | lines | first 3)
    } }
]
