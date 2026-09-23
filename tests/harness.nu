# Minimal test harness: a suite is a list of {name, run} records, where `run` is a
# closure that raises (via `std/assert` or `error make`) when the test fails.

export use std/assert

export def run-suite [suite: string, tests: list<record>] {
    mut failed = 0
    for t in $tests {
        let outcome = (try { do $t.run; null } catch { |e| $e })
        if $outcome == null {
            print $"  ok    ($t.name)"
        } else {
            $failed = $failed + 1
            print $"  FAIL  ($t.name)"
            print $"        ($outcome.msg)"
        }
    }
    print $"($suite): ($tests | length) tests, ($failed) failed"
    if $failed > 0 { exit 1 }
}
