use ./harness.nu *
use ../nexus-cleanup/config.nu *
use ../nexus-cleanup/versions.nu [SCHEMES]
use ../tools/generate-config-schema.nu [config-schema]

def root []: nothing -> string { $env.FILE_PWD | path dirname }
def schema []: nothing -> record { config-schema | from json }
def prop [key: string]: nothing -> record { schema | get properties | get $key }

# Nushell's regex engine handles the ECMA-compatible subset the patterns use:
# anchors, classes, alternation, non-capturing groups and lookahead.
def matches [value: string, pattern: string]: nothing -> bool { $value =~ $pattern }

run-suite "config schema" [
    { name: "the schema declares draft 2020-12 and forbids unknown keys", run: {||
        let s = (schema)
        assert equal $s."$schema" "https://json-schema.org/draft/2020-12/schema"
        assert equal $s.type "object"
        assert equal $s.additionalProperties false
    } }
    { name: "its properties are exactly the recognised, refused and schema keys", run: {||
        let expected = ($CONFIG_KEYS | get key | append ($REFUSED_KEYS | get key) | append $SCHEMA_KEY | sort)
        assert equal (schema | get properties | columns | sort) $expected
    } }
    { name: "refused keys never validate and say why", run: {||
        let execute = (prop "execute")
        assert equal $execute.not {}
        assert ($execute.description | str contains "--execute")
        let password = (prop "password")
        assert equal $password.not {}
        assert ($password.description | str contains "NEXUS_PASSWORD")
    } }
    { name: "each key's type matches the key table", run: {||
        let expected = {string: "string", duration: "string", int: "integer", number: "number", bool: "boolean", "list<string>": "array"}
        for row in $CONFIG_KEYS {
            let p = (prop $row.key)
            assert equal $p.type ($expected | get $row.type) $row.key
            assert equal $p.description $row.description $row.key
        }
        assert equal (prop "repositories" | get items) {type: "string"}
    } }
    { name: "the hosted opt-in is a boolean", run: {||
        assert equal (prop "allow-hosted" | get type) "boolean"
        assert equal (open $"(root)/schema/config.schema.json" | get properties."allow-hosted".type) "boolean"
    } }
    { name: "disabled is a boolean, and enabled is not a key", run: {||
        assert equal (prop "disabled" | get type) "boolean"
        assert not ("enabled" in (schema | get properties | columns))
    } }
    { name: "ranges and enums match the tool's own constants", run: {||
        assert equal (prop "keep" | get minimum) 1
        assert equal (prop "max-attempts" | get minimum) 1
        assert equal (prop "max-deletions" | get minimum) 0
        assert equal (prop "max-deletion-share" | get minimum) 0
        assert equal (prop "max-deletion-share" | get maximum) 1
        assert equal (prop "format" | get enum) $FORMATS
        assert equal (prop "version-scheme" | get enum) ([""] | append $SCHEMES)
    } }
    { name: "every duration the tool accepts matches the schema's pattern", run: {||
        let pattern = (prop "timeout" | get pattern)
        for d in ["30sec" "2min" "1.5sec" ".5sec" "1hr 30min" "1min 1min" "1day" "1wk" "500ms" "10us" "10µs" "5ns" "1_000ms" "1e3ms" " 3sec"] {
            assert (try { $d | into duration; true } catch { false }) $"the tool should accept ($d)"
            assert (matches $d $pattern) $"schema rejects ($d)"
        }
        assert not (matches "30" $pattern)
    } }
    { name: "every value the tool accepted from the fixtures matches its schema pattern", run: {||
        let files = (glob $"($env.FILE_PWD)/fixtures/config/*.yaml")
        mut checked = 0
        for f in $files {
            # Accepted means accepted by the tool as a whole: loaded, then resolved.
            let accepted = (try {
                with-env {NEXUS_URL: "https://nexus.test"} {
                    config resolve {repositories: ["r"]} --file (config load $f)
                }
                true
            } catch { false })
            if not $accepted { continue }
            let doc = (open --raw $f | from yaml)
            if $doc == null { continue }
            for row in ($CONFIG_KEYS | where {|r| ($r.schema.pattern? | default null) != null }) {
                let value = ($doc | get --optional $row.key)
                if $value == null { continue }
                assert (matches ($value | into string) $row.schema.pattern) $"($f | path basename): ($row.key)"
                $checked = $checked + 1
            }
        }
        assert greater $checked 2
    } }
    { name: "the url pattern refuses credentials and accepts a plain address", run: {||
        let p = (prop "url")
        assert (matches "https://nexus.test/path@x" $p.pattern)
        assert not (matches "https://nexus.test/path@x" $p.not.pattern)
        assert (matches "https://bot:pw@nexus.example.invalid" $p.not.pattern)
    } }
    { name: "the path pattern needs both groups", run: {||
        let p = (prop "from-path" | get pattern)
        assert (matches '^/(?P<name>a)/(?P<version>[0-9]{8})/' $p)
        assert not (matches '^/(?P<name>a)/' $p)
        assert (matches "" $p)
    } }
    { name: "the committed schema is the generator's output, byte for byte", run: {||
        assert equal (open --raw $"(root)/schema/config.schema.json") (config-schema)
    } }
    { name: "generating twice gives the same text", run: {||
        assert equal (config-schema) (config-schema)
    } }
]
