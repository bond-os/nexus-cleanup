use ./harness.nu *

def root []: nothing -> string { $env.FILE_PWD | path dirname }
def entrypoint []: nothing -> string { $"(root)/nexus-cleanup.nu" }

# The constant as another script sees it through the module's public surface.
def exported-version []: nothing -> string {
    let r = (^$nu.current-exe -c $"use (root)/nexus-cleanup [VERSION]; $VERSION" | complete)
    assert equal $r.exit_code 0 $"importing VERSION failed: ($r.stderr)"
    $r.stdout | str trim
}

# A clean environment: with no NEXUS_URL, any attempt to resolve configuration
# or enumerate would exit with the usage code instead of 0.
def cli [...args: string]: nothing -> record {
    with-env {NEXUS_URL: "", NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
        ^$nu.current-exe (entrypoint) ...$args | complete
    }
}

run-suite "version" [
    { name: "the module exports VERSION as a semver string", run: {||
        assert ((exported-version) =~ '^\d+\.\d+\.\d+$')
    } }
    { name: "--version prints exactly the version and exits 0 without configuration", run: {||
        let r = (cli "--version")
        assert equal $r.exit_code 0
        assert equal $r.stdout $"(exported-version)\n"
        assert equal $r.stderr ""
    } }
    { name: "--version wins over every other flag, including --execute", run: {||
        let r = (cli "--version" "--execute" "--pattern" "x")
        assert equal $r.exit_code 0
        assert equal $r.stdout $"(exported-version)\n"
        assert equal $r.stderr ""
    } }
    { name: "--version wins over invalid values that would otherwise be usage errors", run: {||
        let r = (cli "--keep" "0" "--format" "yaml" "--version")
        assert equal $r.exit_code 0
        assert equal $r.stdout $"(exported-version)\n"
    } }
]
