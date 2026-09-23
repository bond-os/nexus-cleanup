#!/usr/bin/env nu
# Entrypoint: parse flags, call the module, set the exit code. Nothing else.
#
# Dry run is the default. There is deliberately no --dry-run flag: the safe mode
# is the one you get by forgetting a flag.

use ./nexus-cleanup/config.nu *
use ./nexus-cleanup/api.nu *
use ./nexus-cleanup/run.nu *

def main [
    ...repositories: string             # proxy repositories to clean
    --url: string                       # Nexus base URL (default: $NEXUS_URL)
    --username: string                  # default: $NEXUS_USERNAME
    --password: string                  # default: $NEXUS_PASSWORD
    --pattern: string = ""              # select proxy repositories by glob instead
    --keep: int = 1                     # newest versions to retain per group
    --timeout: duration = 30sec         # per-request timeout
    --max-attempts: int = 4             # attempts per retryable request
    --format: string = "json"           # json or csv
    --version-scheme: string = ""       # force generic, debian, rpm or date
    --scope-from-path: string = ""      # regex with a (?P<scope>...) group
    --from-path: string = ""            # regex with (?P<name>...) and (?P<version>...)
    --execute                           # actually delete; omit for a dry run
    --fail-on-skip                      # exit non-zero if any group was skipped
    --max-deletions: int = 0            # abort an executing run above this many
    --max-deletion-share: float = 0.0   # abort above this share of components
    --summary-out: string = ""          # also write the aggregate here as JSON
] {
    let resolved = (try {
        {ok: (config resolve {
            url: $url
            username: $username
            password: $password
            repositories: $repositories
            pattern: $pattern
            keep: $keep
            timeout: $timeout
            max_attempts: $max_attempts
            format: $format
            version_scheme: $version_scheme
            scope_pattern: $scope_from_path
            from_path: $from_path
            execute: $execute
            fail_on_skip: $fail_on_skip
            max_deletions: $max_deletions
            max_deletion_share: $max_deletion_share
            summary_out: $summary_out
        })}
    } catch {|e| {err: ($e.msg? | default "invalid configuration")} })

    if ("err" in ($resolved | columns)) {
        print --stderr $"nexus-cleanup: ($resolved.err)"
        exit $EXIT_USAGE
    }
    let config = $resolved.ok

    let client = (api client $config.url
        --username $config.username
        --password $config.password
        --timeout $config.timeout
        --max-attempts $config.max_attempts)

    let outcome = (try {
        {ok: (cleanup run $config $client)}
    } catch {|e| {err: ($e.msg? | default "the run failed")} })

    if ("err" in ($outcome | columns)) {
        print --stderr $"nexus-cleanup: ($outcome.err)"
        exit $EXIT_API
    }

    cleanup emit $outcome.ok.report $config.format $config.summary_out
    exit $outcome.ok.exit_code
}
