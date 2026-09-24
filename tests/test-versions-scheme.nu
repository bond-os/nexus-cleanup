use ./harness.nu *
use ../nexus-cleanup/versions.nu *

def scheme [format: string, override?: string]: nothing -> string {
    version scheme-for-format $format $override
}

run-suite "versions: scheme selection" [
    { name: "apt repositories use the debian comparator", run: {||
        assert equal (scheme "apt") "debian"
    } }
    { name: "yum repositories use the rpm comparator", run: {||
        assert equal (scheme "yum") "rpm"
    } }
    { name: "formats with no ecosystem rule use the generic comparator", run: {||
        for f in ["maven2" "npm" "pypi" "nuget" "docker" "raw" "helm" "go" "rubygems"] {
            assert equal (scheme $f) "generic"
        }
    } }
    { name: "an unknown format falls back to generic rather than failing", run: {||
        assert equal (scheme "some-future-format") "generic"
    } }
    { name: "format matching is case-insensitive", run: {||
        assert equal (scheme "APT") "debian"
        assert equal (scheme "Yum") "rpm"
    } }
    { name: "an explicit override wins over every format default", run: {||
        assert equal (scheme "apt" "generic") "generic"
        assert equal (scheme "yum" "debian") "debian"
        assert equal (scheme "maven2" "rpm") "rpm"
    } }
    { name: "an empty override is not an override", run: {||
        assert equal (scheme "apt" "") "debian"
    } }
    { name: "date is accepted as an explicit override", run: {||
        assert equal (scheme "raw" "date") "date"
        assert equal (scheme "apt" "date") "date"
    } }
    { name: "date is never chosen by default for any format", run: {||
        for f in ["raw" "apt" "yum" "maven2" "npm" "pypi" "nuget" "docker" "helm" "conan" "huggingface" "some-future-format"] {
            assert not equal (scheme $f) "date"
        }
    } }
    { name: "an unknown override is refused", run: {||
        assert error {|| version scheme-for-format "apt" "semver" }
    } }
]
