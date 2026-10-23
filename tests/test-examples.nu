use ./harness.nu *
use ../nexus-cleanup/scaffold.nu *
use ../nexus-cleanup/version.nu [VERSION]
use ../tools/render-examples.nu [example-plan]

# examples/<ci>/ is `init` output plus release markers, rendered by
# tools/render-examples.nu. These tests keep the committed trees equal to what the
# templates produce, and check that every pin in them is one release-please moves.

def examples []: nothing -> string { $env.FILE_PWD | path dirname | path join "examples" }

def tree [dir: string]: nothing -> list<string> {
    glob $"($dir)/**/*" --no-dir | path relative-to $dir | sort
}

def read [path: string]: nothing -> string { open --raw $path | decode utf-8 }

# What release-please's `generic` updater does to a file: on a line carrying
# x-release-please-version, and on every line between x-release-please-start-version
# and x-release-please-end, the first X.Y.Z becomes the new version. Only the first:
# its VERSION_REGEX has no `g` flag, so a second pin on the same line never moves.
def bump [text: string, version: string]: nothing -> string {
    mut in_block = false
    mut out = []
    for line in ($text | split row "\n") {
        if ($line | str contains "x-release-please-start-version") {
            $in_block = true
            $out = ($out | append $line)
        } else if ($line | str contains "x-release-please-end") {
            $in_block = false
            $out = ($out | append $line)
        } else if $in_block or ($line | str contains "x-release-please-version") {
            $out = ($out | append ($line | str replace --regex '\d+\.\d+\.\d+' $version))
        } else {
            $out = ($out | append $line)
        }
    }
    $out | str join "\n"
}

# Lines naming the tool's version: the image tag, the release tag, the schema URL.
def pinned-lines [text: string]: nothing -> list<string> {
    $text | lines | where {|l| $l =~ 'nexus-cleanup:\d|/v\d+\.\d+\.\d+/schema/|NEXUS_CLEANUP_VERSION: v\d' }
}

# Whether a line is covered by a marker: inline, or inside a start/end block.
def unmarked-pins [text: string]: nothing -> list<string> {
    mut in_block = false
    mut missing = []
    for line in ($text | lines) {
        if ($line | str contains "x-release-please-start-version") { $in_block = true; continue }
        if ($line | str contains "x-release-please-end") { $in_block = false; continue }
        let pinned = ($line =~ 'nexus-cleanup:\d|/v\d+\.\d+\.\d+/schema/|NEXUS_CLEANUP_VERSION: v\d')
        if $pinned and not $in_block and not ($line | str contains "x-release-please-version") {
            $missing = ($missing | append $line)
        }
    }
    $missing
}

def parse-by-kind [path: string, text: string] {
    let name = ($path | path basename)
    if ($name | str ends-with ".yml") or ($name | str ends-with ".yaml") {
        $text | from yaml | ignore
    } else if ($name | str ends-with ".json") {
        $text | from json | ignore
    } else if ($name | str ends-with ".xml") {
        $text | from xml | ignore
    }
}

run-suite "examples" [
    { name: "examples/ holds the configuration gallery and one tree per CI system", run: {||
        let dirs = (ls (examples) | where type == dir | get name | path basename | sort)
        assert equal $dirs (["configs"] | append ($CI_SYSTEMS | columns) | sort)
    } }
    { name: "each example tree is the renderer's output, byte for byte, and nothing else", run: {||
        for ci in ($CI_SYSTEMS | columns) {
            let dir = (examples | path join $ci)
            let plan = (example-plan $ci)
            assert equal (tree $dir) ($plan | get path | sort) $"examples/($ci): run nu tools/render-examples.nu"
            for f in $plan {
                assert equal (read ($dir | path join $f.path)) $f.content $"examples/($ci)/($f.path) differs: run nu tools/render-examples.nu"
            }
        }
    } }
    { name: "every rendered example parses: YAML, JSON with comments, XML", run: {||
        for ci in ($CI_SYSTEMS | columns) {
            for f in (example-plan $ci) {
                let parsed = (try { parse-by-kind $f.path $f.content; true } catch { false })
                assert $parsed $"examples/($ci)/($f.path)"
            }
        }
    } }
    { name: "the modeline survives the markers as a line of its own ending in the URL", run: {||
        let url = $"https://raw.githubusercontent.com/bond-os/nexus-cleanup/v($VERSION)/schema/config.schema.json"
        for ci in ($CI_SYSTEMS | columns) {
            let example = (example-plan $ci | where path == "configs/example.yaml" | get content.0)
            assert ($example | lines | any {|l| $l == $"# yaml-language-server: $schema=($url)" }) $ci
        }
    } }
    { name: "every pinned line carries a release marker", run: {||
        for ci in ($CI_SYSTEMS | columns) {
            let plan = (example-plan $ci)
            assert greater ($plan | each {|f| pinned-lines $f.content | length } | math sum) 0 $ci
            for f in $plan {
                assert equal (unmarked-pins $f.content) [] $"examples/($ci)/($f.path)"
            }
        }
    } }
    { name: "a release bump of the committed examples equals rendering at the new version", run: {||
        for ci in ($CI_SYSTEMS | columns) {
            let next = (scaffold plan --ci $ci --editor [vscode intellij] --version "9.8.7" --release-markers)
            for f in $next {
                let committed = (read (examples | path join $ci $f.path))
                assert equal (bump $committed "9.8.7") $f.content $"examples/($ci)/($f.path)"
            }
        }
    } }
    { name: "every example file holding a pin is a release-please extra-file", run: {||
        let root = ($env.FILE_PWD | path dirname)
        let extra = (open ($root | path join "release-please-config.json") | get packages | get "." | get extra-files | get path)
        for ci in ($CI_SYSTEMS | columns) {
            for f in (example-plan $ci) {
                if ($f.content | str contains "x-release-please") {
                    assert ($"examples/($ci)/($f.path)" in $extra) $"examples/($ci)/($f.path)"
                }
            }
        }
        let missing = ($extra | where {|p| not ($root | path join $p | path exists) })
        assert equal $missing [] "an extra-file that does not exist"
    } }
]

# The README names the current release in its examples and prose; release-please
# moves each mention only if a marker covers it.
def readme []: nothing -> string { read ($env.FILE_PWD | path dirname | path join "README.md") }

# Lines holding VERSION as a whole X.Y.Z, so that 10.2.0 or 0.2.0.1 do not count.
def version-lines [text: string, version: string]: nothing -> list<string> {
    let re = '(?<![0-9.])' + ($version | str replace --all "." '\.') + '(?![0-9])'
    $text | lines | where {|l| $l =~ $re }
}

# Every X.Y.Z the README gives as the tool's: an image tag or a release tag.
def tool-versions [text: string]: nothing -> list<string> {
    $text | parse --regex '(?:nexus-cleanup:|(?<![\w.])v)(?P<v>[0-9]+\.[0-9]+\.[0-9]+)' | get v
}

run-suite "README" [
    { name: "every image and release tag in the README is the current release", run: {||
        let found = (tool-versions (readme))
        assert greater ($found | length) 0
        assert equal ($found | where {|v| $v != $VERSION } | uniq) [] "update the README to the current release"
    } }
    { name: "a release bump leaves no mention of the previous release", run: {||
        assert equal (version-lines (bump (readme) "9.8.7") $VERSION) [] "add an x-release-please marker"
    } }
    { name: "a release bump changes the tool's version only", run: {||
        let before = (readme | lines)
        let after = (bump (readme) "9.8.7" | lines)
        let changed = ($before | zip $after | where {|p| $p.0 != $p.1 })
        let foreign = ($changed | where {|p| ($p.0 | str replace --all $VERSION "9.8.7") != $p.1 } | each {|p| $p.0 })
        assert equal $foreign [] "a marked line holding another X.Y.Z"
    } }
]
