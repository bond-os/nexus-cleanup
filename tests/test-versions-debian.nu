use ./harness.nu *
use ../nexus-cleanup/versions.nu *

# Cases follow dpkg's own version-comparison semantics (deb-version(7), dpkg's
# libdpkg version test corpus).
def cmp [a: string, b: string]: nothing -> int { version compare "debian" $a $b }
def ok [v: string]: nothing -> bool { version parseable "debian" $v }

run-suite "versions: debian" [
    { name: "identical versions compare equal", run: {||
        assert equal (cmp "1.0" "1.0") 0
        assert equal (cmp "1.0-1" "1.0-1") 0
    } }
    { name: "leading zeros in a numeric run are insignificant", run: {||
        assert equal (cmp "0" "00") 0
        assert equal (cmp "1.0" "1.00") 0
    } }

    # --- epochs ---
    { name: "an epoch outranks a larger upstream version", run: {||
        assert equal (cmp "1:1.0" "2.0") 1
        assert equal (cmp "2.0" "1:1.0") (-1)
    } }
    { name: "an absent epoch means zero", run: {||
        assert equal (cmp "0:1.0" "1.0") 0
    } }
    { name: "epochs compare numerically", run: {||
        assert equal (cmp "10:1" "9:1") 1
    } }
    { name: "the spec's epoch case: 1:2.3-4 outranks 2.3-4", run: {||
        assert equal (cmp "1:2.3-4" "2.3-4") 1
    } }

    # --- revisions ---
    { name: "revisions compare when upstream is equal", run: {||
        assert equal (cmp "1.0-1" "1.0-2") (-1)
    } }
    { name: "an absent revision ranks below any revision", run: {||
        assert equal (cmp "1.0" "1.0-1") (-1)
    } }
    { name: "a distribution suffix in the revision ranks above the bare revision", run: {||
        assert equal (cmp "2.3-4ubuntu1" "2.3-4") 1
    } }

    # --- the tilde, which sorts before everything including end of string ---
    { name: "a tilde suffix ranks below the plain version", run: {||
        assert equal (cmp "1.0~rc1" "1.0") (-1)
        assert equal (cmp "1.0~" "1.0") (-1)
    } }
    { name: "tildes compare against each other", run: {||
        assert equal (cmp "1.0~rc1" "1.0~rc2") (-1)
        assert equal (cmp "1.0~~" "1.0~") (-1)
    } }
    { name: "a tilde works inside the revision too", run: {||
        assert equal (cmp "1.0-1~" "1.0-1") (-1)
    } }

    # --- character ordering: letters before everything non-alphanumeric ---
    { name: "a letter suffix ranks above the bare version", run: {||
        assert equal (cmp "1.0a" "1.0") 1
        assert equal (cmp "1.0" "1.0a") (-1)
    } }
    { name: "non-alphanumerics rank above letters", run: {||
        assert equal (cmp "1.0+1" "1.0a") 1
    } }
    { name: "numeric runs compare numerically, not lexically", run: {||
        assert equal (cmp "1.10" "1.9") 1
        assert equal (cmp "1.0-10" "1.0-9") 1
    } }

    # --- parseability ---
    { name: "ordinary debian versions are parseable", run: {||
        assert (ok "1.0")
        assert (ok "0")
        assert (ok "1.0-1")
        assert (ok "1:2.3-4ubuntu1")
        assert (ok "1.0~rc1")
        assert (ok "2.3+dfsg-1")
    } }
    { name: "non-versions and disallowed characters are not parseable", run: {||
        assert not (ok "latest")
        assert not (ok "")
        assert not (ok "abc")
        assert not (ok "-1")
        assert not (ok "1.0_2")
        assert not (ok "1.0 2")
        assert not (ok ":1.0")
    } }
    { name: "comparing an unparseable version raises rather than guessing", run: {||
        assert error {|| version compare "debian" "latest" "1.0" }
        assert error {|| version compare "debian" "1.0" "latest" }
    } }
]
