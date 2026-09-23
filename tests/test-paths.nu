use ./harness.nu *
use ../nexus-cleanup/paths.nu *

# The motivating configuration's pattern, verbatim.
const PATTERN = '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'

def at [path: string]: nothing -> record {
    {format: "raw", group: ($path | path dirname), name: $path, version: "", assets: [{path: $path}]}
}

def m [path: string]: nothing -> any { path match (at $path) $PATTERN }

run-suite "paths" [
    { name: "a date directory yields its parent as name and itself as version", run: {||
        assert equal (m "/some_dir/20250101/app.tar.gz") {name: "some_dir", version: "20250101"}
    } }
    { name: "suffixed date directories match with the full directory name", run: {||
        assert equal (m "/some_dir/20250103-hotfix/app.tar.gz" | get version) "20250103-hotfix"
        assert equal (m "/some_dir/20250103hotfix/app.tar.gz" | get version) "20250103hotfix"
    } }
    { name: "nested files belong to their date directory", run: {||
        assert equal (m "/some_dir/20250103_2/nested/deep/file.bin") {name: "some_dir", version: "20250103_2"}
    } }
    { name: "the second parent is distinguished by name", run: {||
        assert equal (m "/some_other_dir/20240615/x" | get name) "some_other_dir"
    } }
    { name: "semver-like directories never match", run: {||
        for p in ["/some_dir/3.2.4.24-something/app.tar.gz" "/some_dir/3.2.5/app.tar.gz"] {
            assert equal (m $p) null
        }
    } }
    { name: "an eight-digit semver major never matches", run: {||
        assert equal (m "/some_dir/12345678.0.1/app.tar.gz") null
    } }
    { name: "a seven-digit directory never matches", run: {||
        assert equal (m "/some_dir/2025010/app.tar.gz") null
    } }
    { name: "a file directly under the parent never matches", run: {||
        assert equal (m "/some_dir/app-at-top-level.tar.gz") null
    } }
    { name: "a parent the pattern does not name never matches", run: {||
        assert equal (m "/elsewhere/20250101/app.tar.gz") null
    } }
    { name: "a component with no assets never matches", run: {||
        assert equal (path match {format: "raw", assets: []} $PATTERN) null
        assert equal (path match {format: "raw"} $PATTERN) null
    } }
    { name: "a match with an empty name or version is no match", run: {||
        assert equal (path match (at "/x/y") '^/(?P<name>x)/(?P<version>)') null
    } }
]
