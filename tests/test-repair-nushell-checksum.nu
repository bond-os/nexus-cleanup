use ./harness.nu *

const OLD = "13ef75df08df30f8d7b031df538e82a52c6e74ce839b1a9091c3a3f1969c3742"
const DOWNLOAD = "a4d451ec23463726f72c43d64c710968f6b602cd653b4de8adee1b556240a829"

def fixture [text: string]: nothing -> record {
    let work = (mktemp -d -t "repair-nushell-XXXXXX")
    let template = $"($work)/template.yml"
    let example = $"($work)/example.yml"
    let downloader = $"($work)/curl"
    $text | save --raw $template
    $text | save --raw $example
    '#!/bin/sh
set -eu
out=
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then out=$2; shift 2; continue; fi
  shift
done
printf release > "$out"
' | save --raw $downloader
    ^chmod +x $downloader
    {work: $work, template: $template, example: $example, downloader: $downloader}
}

def content [version: string, checksum: string]: nothing -> string {
    $"name: test\n\nenv:\n  NU_VERSION: ($version)\n  NU_SHA256: ($checksum)\n"
}

def run-repair [case: record]: nothing -> record {
    with-env {CURL_BIN: $case.downloader} {
        ^sh .github/scripts/repair-nushell-checksum.sh $case.template $case.example | complete
    }
}

run-suite "repair-nushell-checksum.sh" [
    { name: "a stale checksum pair is replaced and unrelated content is preserved", run: {||
        let case = (fixture ((content "0.117.0" $OLD) + "run: unchanged\n"))
        let result = (run-repair $case)
        assert equal $result.exit_code 0
        assert ($result.stdout | str contains $DOWNLOAD)
        assert (open --raw $case.template | str contains $"NU_SHA256: ($DOWNLOAD)")
        assert (open --raw $case.example | str contains $"NU_SHA256: ($DOWNLOAD)")
        assert (open --raw $case.template | str ends-with "run: unchanged\n")
        rm -rf $case.work
    } }
    { name: "an already matching checksum is left byte-for-byte unchanged", run: {||
        let text = (content "0.117.0" $DOWNLOAD)
        let case = (fixture $text)
        let result = (run-repair $case)
        assert equal $result.exit_code 0
        assert equal (open --raw $case.template) $text
        assert equal (open --raw $case.example) $text
        rm -rf $case.work
    } }
    { name: "a malformed version is refused before download or writes", run: {||
        let case = (fixture (content "latest" $OLD))
        let before = (open --raw $case.template)
        let result = (run-repair $case)
        assert not equal $result.exit_code 0
        assert equal (open --raw $case.template) $before
        assert equal (open --raw $case.example) $before
        rm -rf $case.work
    } }
    { name: "a duplicate checksum is refused without changing either file", run: {||
        let text = ((content "0.117.0" $OLD) + $"  NU_SHA256: ($OLD)\n")
        let case = (fixture $text)
        let result = (run-repair $case)
        assert not equal $result.exit_code 0
        assert equal (open --raw $case.template) $text
        assert equal (open --raw $case.example) $text
        rm -rf $case.work
    } }
    { name: "a malformed extra checksum is refused without changing either file", run: {||
        let text = ((content "0.117.0" $OLD) + "  NU_SHA256: invalid\n")
        let case = (fixture $text)
        let result = (run-repair $case)
        assert not equal $result.exit_code 0
        assert equal (open --raw $case.template) $text
        assert equal (open --raw $case.example) $text
        rm -rf $case.work
    } }
    { name: "different versions are refused without changing either file", run: {||
        let case = (fixture (content "0.117.0" $OLD))
        $"env:\n  NU_VERSION: 0.116.1\n  NU_SHA256: ($OLD)\n" | save --force --raw $case.example
        let before_template = (open --raw $case.template)
        let before_example = (open --raw $case.example)
        let result = (run-repair $case)
        assert not equal $result.exit_code 0
        assert equal (open --raw $case.template) $before_template
        assert equal (open --raw $case.example) $before_example
        rm -rf $case.work
    } }
    { name: "different checksums are refused without changing either file", run: {||
        let case = (fixture (content "0.117.0" $OLD))
        (content "0.117.0" $DOWNLOAD) | save --force --raw $case.example
        let before_template = (open --raw $case.template)
        let before_example = (open --raw $case.example)
        let result = (run-repair $case)
        assert not equal $result.exit_code 0
        assert equal (open --raw $case.template) $before_template
        assert equal (open --raw $case.example) $before_example
        rm -rf $case.work
    } }
]
