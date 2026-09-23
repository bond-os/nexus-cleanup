#!/usr/bin/env nu
# Discovers and runs every tests/test-*.nu. Exits non-zero if any suite fails.

def main []: nothing -> nothing {
    let dir = $env.FILE_PWD
    let files = (glob $"($dir)/test-*.nu" | sort)

    if ($files | is-empty) {
        print --stderr "run-tests: no test-*.nu files found"
        exit 1
    }

    mut failed = []
    for f in $files {
        let name = ($f | path basename)
        print $"── ($name)"
        let result = (^$nu.current-exe $f | complete)
        print ($result.stdout | str trim --right)
        if ($result.stderr | is-not-empty) { print --stderr ($result.stderr | str trim --right) }
        if $result.exit_code != 0 { $failed = ($failed | append $name) }
    }

    print ""
    if ($failed | is-empty) {
        print $"All ($files | length) suites passed."
    } else {
        print --stderr $"Failed suites: ($failed | str join ', ')"
        exit 1
    }
}
