use ./harness.nu *
use ../nexus-cleanup/versions.nu *

def cmp [a: string, b: string]: nothing -> int { version compare "generic" $a $b }
def ok [v: string]: nothing -> bool { version parseable "generic" $v }

run-suite "versions: generic" [
    # --- dotted numeric cores, including unequal lengths ---
    { name: "numeric segments compare numerically, not lexically", run: {||
        assert equal (cmp "1.9.0" "1.10.0") (-1)
        assert equal (cmp "1.10.0" "1.9.0") 1
    } }
    { name: "shorter core is zero-padded, so 1.0 equals 1.0.0", run: {||
        assert equal (cmp "1.0" "1.0.0") 0
        assert equal (cmp "1.0.0" "1.0") 0
    } }
    { name: "shorter core is still ordered when the padding matters", run: {||
        assert equal (cmp "1.0" "1.0.1") (-1)
        assert equal (cmp "2" "1.9.9") 1
    } }
    { name: "leading v is ignored", run: {||
        assert equal (cmp "v1.2.3" "1.2.3") 0
        assert equal (cmp "v1.2.3" "v1.2.4") (-1)
    } }

    # --- semver pre-release ranks below its release ---
    { name: "a pre-release ranks below the release it precedes", run: {||
        assert equal (cmp "1.0.0-rc1" "1.0.0") (-1)
        assert equal (cmp "1.0.0" "1.0.0-rc1") 1
    } }
    { name: "pre-release identifiers compare left to right", run: {||
        assert equal (cmp "1.0.0-rc1" "1.0.0-rc2") (-1)
        assert equal (cmp "1.0.0-alpha" "1.0.0-beta") (-1)
    } }
    { name: "fewer pre-release identifiers ranks lower when the prefix is equal", run: {||
        assert equal (cmp "1.0.0-alpha" "1.0.0-alpha.1") (-1)
    } }
    { name: "numeric pre-release identifiers rank below alphanumeric ones", run: {||
        assert equal (cmp "1.0.0-alpha.1" "1.0.0-alpha.beta") (-1)
    } }
    { name: "numeric pre-release identifiers compare numerically", run: {||
        assert equal (cmp "1.0.0-alpha.2" "1.0.0-alpha.10") (-1)
    } }

    # --- build metadata is ignored ---
    { name: "build metadata does not affect ordering", run: {||
        assert equal (cmp "1.0.0+build1" "1.0.0+build2") 0
        assert equal (cmp "1.0.0+build" "1.0.0") 0
    } }
    { name: "build metadata is ignored but the rest still orders", run: {||
        assert equal (cmp "1.0.0+b" "1.0.1+a") (-1)
        assert equal (cmp "1.0.0-rc1+b" "1.0.0+a") (-1)
    } }

    # --- parseability ---
    { name: "ordinary versions are parseable", run: {||
        assert (ok "1.2.3")
        assert (ok "v1.2.3")
        assert (ok "1")
        assert (ok "20240101")
        assert (ok "1.2.3-rc.1")
        assert (ok "1.2.3-rc.1+build.5")
    } }
    { name: "non-version strings are not parseable", run: {||
        assert not (ok "latest")
        assert not (ok "stable")
        assert not (ok "")
        assert not (ok "1.2.x")
        assert not (ok "release-2024")
    } }
    { name: "malformed pre-release or build sections are not parseable", run: {||
        assert not (ok "1.2.3-")
        assert not (ok "1.2.3+")
        assert not (ok "1..2")
        assert not (ok "1.2.3-rc..1")
    } }

    # --- comparing an unparseable version is an error, never a guess ---
    { name: "comparing an unparseable version raises rather than guessing", run: {||
        assert error {|| version compare "generic" "latest" "1.0.0" }
        assert error {|| version compare "generic" "1.0.0" "latest" }
    } }
]
