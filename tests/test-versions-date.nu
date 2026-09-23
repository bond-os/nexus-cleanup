use ./harness.nu *
use ../nexus-cleanup/versions.nu *

def cmp [a: string, b: string]: nothing -> int { version compare "date" $a $b }
def ok [v: string]: nothing -> bool { version parseable "date" $v }

run-suite "versions: date" [
    { name: "dates order chronologically across months and years", run: {||
        assert equal (cmp "20241231" "20250101") (-1)
        assert equal (cmp "20250102" "20250101") 1
        assert equal (cmp "20250131" "20250201") (-1)
        assert equal (cmp "20250101" "20250101") 0
    } }
    { name: "a same-day respin ranks above the bare date", run: {||
        assert equal (cmp "20250103" "20250103-hotfix") (-1)
        assert equal (cmp "20250103-hotfix" "20250103") 1
    } }
    { name: "a later date outranks an earlier date's respin", run: {||
        assert equal (cmp "20250103-hotfix" "20250104") (-1)
    } }
    { name: "respins order naturally, digit runs numerically", run: {||
        assert equal (cmp "20250103-hotfix2" "20250103-hotfix10") (-1)
        assert equal (cmp "20250103-rc9" "20250103-rc10") (-1)
        assert equal (cmp "20250103-a" "20250103-b") (-1)
    } }
    { name: "a longer suffix sharing a prefix ranks above the shorter one", run: {||
        assert equal (cmp "20250103-hotfix" "20250103-hotfix2") (-1)
    } }
    { name: "a suffix without a separator parses and orders as a respin", run: {||
        assert (ok "20250103hotfix")
        assert equal (cmp "20250103" "20250103hotfix") (-1)
    } }
    { name: "a leap day is a real date", run: {||
        assert (ok "20240229")
    } }
    { name: "impossible calendar dates are rejected", run: {||
        for v in ["20250229" "20251399" "20250100" "20250132" "00000000"] { assert not (ok $v) }
    } }
    { name: "non-date versions are rejected", run: {||
        for v in ["3.2.5" "3.2.4.24-something" "2025010" "202501011" "" "latest" "v20250101"] { assert not (ok $v) }
    } }
    { name: "suffixed forms seen in the motivating layout parse", run: {||
        for v in ["20250103-hotfix" "20250103_2" "20250103hotfix" "20250103.nightly"] { assert (ok $v) }
    } }
    { name: "comparing an unparseable date raises rather than guessing", run: {||
        assert error {|| version compare "date" "20250229" "20250101" }
        assert error {|| version compare "date" "20250101" "3.2.5" }
    } }
]
