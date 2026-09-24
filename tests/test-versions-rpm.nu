use ./harness.nu *
use ../nexus-cleanup/versions.nu *

# Cases follow rpm's own rpmvercmp test data (rpmio/test/rpmvercmp.at).
def cmp [a: string, b: string]: nothing -> int { version compare "rpm" $a $b }
def ok [v: string]: nothing -> bool { version parseable "rpm" $v }

run-suite "versions: rpm" [
    { name: "identical versions compare equal", run: {||
        assert equal (cmp "1.0" "1.0") 0
        assert equal (cmp "2.0.1" "2.0.1") 0
        assert equal (cmp "5.5p1" "5.5p1") 0
    } }
    { name: "numeric segments order numerically", run: {||
        assert equal (cmp "1.0" "2.0") (-1)
        assert equal (cmp "2.0" "1.0") 1
        assert equal (cmp "5.5p10" "5.5p2") 1
    } }
    { name: "a longer version outranks its prefix", run: {||
        assert equal (cmp "2.0" "2.0.1") (-1)
        assert equal (cmp "2.0.1" "2.0") 1
    } }
    { name: "an alphabetic segment outranks the bare numeric version", run: {||
        assert equal (cmp "2.0.1a" "2.0.1") 1
        assert equal (cmp "1a" "1") 1
        assert equal (cmp "1" "1a") (-1)
    } }
    { name: "a numeric segment outranks an alphabetic one at the same position", run: {||
        assert equal (cmp "10xyz" "10.1xyz") (-1)
        assert equal (cmp "xyz10" "xyz10.1") (-1)
    } }
    { name: "alphabetic segments compare lexically", run: {||
        assert equal (cmp "b" "a") 1
        assert equal (cmp "5.5p1" "5.5p2") (-1)
    } }
    { name: "leading zeros in a numeric segment are insignificant", run: {||
        assert equal (cmp "01" "1") 0
        assert equal (cmp "012" "12") 0
    } }
    { name: "any run of separators is equivalent", run: {||
        assert equal (cmp "a+" "a+") 0
        assert equal (cmp "a+" "a_") 0
        assert equal (cmp "1.0" "1_0") 0
    } }

    # --- tilde sorts before everything ---
    { name: "a tilde suffix ranks below the plain version", run: {||
        assert equal (cmp "1.0~rc1" "1.0") (-1)
        assert equal (cmp "1.0" "1.0~rc1") 1
    } }
    { name: "tildes compare against each other", run: {||
        assert equal (cmp "1.0~rc1" "1.0~rc2") (-1)
        assert equal (cmp "1.0~rc1~git123" "1.0~rc1") (-1)
    } }

    # --- caret sorts after the base version but below the next release ---
    { name: "a caret suffix ranks above the plain version", run: {||
        assert equal (cmp "1.0^" "1.0") 1
        assert equal (cmp "1.0" "1.0^") (-1)
        assert equal (cmp "1.0^" "1.0^") 0
    } }
    { name: "caret content compares, and stays below the next release", run: {||
        assert equal (cmp "1.0^git1" "1.0") 1
        assert equal (cmp "1.0^git1" "1.0^git2") (-1)
        assert equal (cmp "1.0^20160101" "1.0.1") (-1)
    } }
    { name: "tilde inside a caret segment still ranks below it", run: {||
        assert equal (cmp "1.0^git1~pre" "1.0^git1") (-1)
    } }

    # --- epoch and release ---
    { name: "an epoch outranks a larger version", run: {||
        assert equal (cmp "1:1.0" "2.0") 1
        assert equal (cmp "0:1.0" "1.0") 0
    } }
    { name: "the release is compared after the version", run: {||
        assert equal (cmp "1.2.3-1.el9" "1.2.3-2.el9") (-1)
        assert equal (cmp "1.2.3-2.el9" "1.2.3-10.el9") (-1)
    } }

    # --- parseability ---
    { name: "ordinary rpm versions are parseable", run: {||
        assert (ok "1.0")
        assert (ok "1.2.3-1.el9")
        assert (ok "1:1.2.3-1")
        assert (ok "1.0~rc1")
        assert (ok "1.0^20160101")
        assert (ok "5.5p1")
    } }
    { name: "non-versions and disallowed characters are not parseable", run: {||
        assert not (ok "")
        assert not (ok "-1")
        assert not (ok ":1.0")
        assert not (ok "1.0 2")
        assert not (ok "1.0/2")
    } }
    { name: "comparing an unparseable version raises rather than guessing", run: {||
        assert error {|| version compare "rpm" "" "1.0" }
        assert error {|| version compare "rpm" "1.0" "1.0/2" }
    } }
]
