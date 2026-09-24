use ./harness.nu *
use ../tools/record-fixtures.nu [PLACEHOLDER_HOST]

# Guards the committed fixtures: a careless re-record must not leak the
# reference instance into the repository.

def fixture-files []: nothing -> list<string> {
    glob $"($env.FILE_PWD)/fixtures/**/*.json"
}

def all-text []: nothing -> string {
    fixture-files | each {|f| open --raw $f } | str join "\n"
}

def download-urls []: nothing -> list<string> {
    fixture-files
    | each {|f|
        let doc = (open $f)
        let items = ($doc.items? | default [])
        $items | each {|c| ($c.assets? | default []) | each {|a| $a.downloadUrl? | default "" } }
    }
    | flatten
    | flatten
    | where {|u| ($u | is-not-empty) }
}

def values-of [field: string]: nothing -> list<string> {
    # Built by concatenation: in an interpolated string `(` opens an expression,
    # which would swallow the regex group.
    let re = ('"' + $field + '": "(?P<v>[^"]*)"')
    all-text | parse --regex $re | get v | uniq | sort
}

run-suite "fixtures are clean" [
    { name: "there are fixtures to check, so this suite cannot pass vacuously", run: {||
        assert greater (fixture-files | length) 1
    } }
    { name: "redaction demonstrably ran", run: {||
        assert ((all-text) | str contains $PLACEHOLDER_HOST)
    } }
    { name: "no uploader identity survives", run: {||
        assert equal (values-of "uploader") ["redacted-user"]
    } }
    { name: "no uploader IP survives", run: {||
        assert equal (values-of "uploaderIp") ["0.0.0.0"]
    } }
    { name: "no blob store name survives", run: {||
        assert equal (values-of "blobStoreName") ["redacted-blobstore"]
    } }
    { name: "no blob reference survives", run: {||
        # blobRef embeds the blob store name and its UUID.
        assert equal (values-of "blobRef") ["redacted-blobref"]
    } }
    { name: "every downloadUrl points at the placeholder host", run: {||
        let hosts = (download-urls | each {|u| $u | url parse | get host } | uniq | sort)
        assert equal $hosts [$PLACEHOLDER_HOST]
    } }
    { name: "no authorization header was ever written to a fixture", run: {||
        # `http --full` echoes back the request's Authorization header; the
        # recorder must save response bodies only. Matched by shape, not by the
        # bare word: package names like microsoft.aspnetcore.authorization are
        # legitimate fixture content.
        let text = (all-text)
        assert equal ($text | parse --regex 'Basic [A-Za-z0-9+/]{8,}={0,2}' | length) 0
        assert equal ($text | parse --regex '(?i)"authorization"\s*:' | length) 0
        assert equal ($text | parse --regex '(?i)"name"\s*:\s*"authorization"' | length) 0
    } }
    { name: "fixtures are response bodies, not whole response records", run: {||
        for f in (fixture-files) {
            let doc = (open $f)
            if ($doc | describe --detailed | get type) == "record" {
                let cols = ($doc | columns)
                assert not ("headers" in $cols)
                assert not ("urls" in $cols)
            }
        }
    } }
]
