# Environment and flag resolution, validated before any request is made.
#
# The environment supplies connection settings; an equivalent flag overrides it.
# Everything is checked up front, so a mistyped value fails before a single
# component is enumerated rather than halfway through a deletion pass.

use ./versions.nu [SCHEMES]

export const EXIT_OK = 0
export const EXIT_DELETION_FAILURES = 1
export const EXIT_USAGE = 2
export const EXIT_API = 3
export const EXIT_SKIPPED = 4
export const EXIT_CAP = 5

export const FORMATS = ["json" "csv"]

def usage-error [message: string] {
    error make {msg: $"usage: ($message)"}
}

def env-or [name: string, override: any]: nothing -> string {
    if ($override != null) and (($override | into string) | is-not-empty) {
        return ($override | into string)
    }
    $env | get --optional $name | default ""
}

# Resolve configuration from the environment, overridden by any supplied flags.
# Raises a usage error naming the offending setting.
export def "config resolve" [overrides: record = {}]: nothing -> record {
    let url = (env-or "NEXUS_URL" ($overrides.url? | default null))
    if ($url | is-empty) {
        usage-error "NEXUS_URL is not set and no --url was given"
    }
    if not ($url | str starts-with "http") {
        usage-error $"NEXUS_URL must be an http or https URL, got '($url)'"
    }

    let keep = ($overrides.keep? | default 1)
    if $keep < 1 { usage-error $"--keep must be at least 1, got ($keep)" }

    let timeout = ($overrides.timeout? | default 30sec)
    if $timeout <= 0sec { usage-error $"--timeout must be positive, got ($timeout)" }

    let max_attempts = ($overrides.max_attempts? | default 4)
    if $max_attempts < 1 { usage-error $"--max-attempts must be at least 1, got ($max_attempts)" }

    let format = ($overrides.format? | default "json")
    if $format not-in $FORMATS {
        usage-error $"--format must be one of ($FORMATS | str join ', '), got '($format)'"
    }

    let version_scheme = ($overrides.version_scheme? | default "")
    if ($version_scheme | is-not-empty) and ($version_scheme not-in $SCHEMES) {
        usage-error $"--version-scheme must be one of ($SCHEMES | str join ', '), got '($version_scheme)'"
    }

    let scope_pattern = ($overrides.scope_pattern? | default "")
    if ($scope_pattern | is-not-empty) {
        if not ($scope_pattern | str contains "(?P<scope>") {
            usage-error "--scope-from-path must contain a named group (?P<scope>...)"
        }
        let compiles = (try { "probe" | parse --regex $scope_pattern; true } catch { false })
        if not $compiles {
            usage-error $"--scope-from-path is not a valid expression: '($scope_pattern)'"
        }
    }

    let from_path = ($overrides.from_path? | default "")
    if ($from_path | is-not-empty) {
        if not (($from_path | str contains "(?P<name>") and ($from_path | str contains "(?P<version>")) {
            usage-error "--from-path must contain both (?P<name>...) and (?P<version>...) groups"
        }
        let compiles = (try { "probe" | parse --regex $from_path; true } catch { false })
        if not $compiles {
            usage-error $"--from-path is not a valid expression: '($from_path)'"
        }
    }

    let repositories = ($overrides.repositories? | default [])
    let pattern = ($overrides.pattern? | default "")
    if ($repositories | is-empty) and ($pattern | is-empty) {
        usage-error "name at least one repository, or supply --pattern"
    }

    let max_deletions = ($overrides.max_deletions? | default 0)
    if $max_deletions < 0 { usage-error $"--max-deletions cannot be negative, got ($max_deletions)" }

    let max_deletion_share = ($overrides.max_deletion_share? | default 0.0)
    if $max_deletion_share < 0.0 or $max_deletion_share > 1.0 {
        usage-error $"--max-deletion-share must be between 0 and 1, got ($max_deletion_share)"
    }

    {
        url: ($url | str trim --right --char "/")
        username: (env-or "NEXUS_USERNAME" ($overrides.username? | default null))
        password: (env-or "NEXUS_PASSWORD" ($overrides.password? | default null))
        repositories: $repositories
        pattern: $pattern
        keep: $keep
        timeout: $timeout
        max_attempts: $max_attempts
        format: $format
        version_scheme: $version_scheme
        scope_pattern: $scope_pattern
        from_path: $from_path
        execute: ($overrides.execute? | default false)
        fail_on_skip: ($overrides.fail_on_skip? | default false)
        max_deletions: $max_deletions
        max_deletion_share: $max_deletion_share
        summary_out: ($overrides.summary_out? | default "")
    }
}
