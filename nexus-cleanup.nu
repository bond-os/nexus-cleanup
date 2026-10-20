#!/usr/bin/env nu
# Entrypoint: parse flags, call the module, set the exit code. Nothing else.
#
# Dry run is the default. There is deliberately no --dry-run flag: the safe mode
# is the one you get by forgetting a flag.

use ./nexus-cleanup/config.nu *
use ./nexus-cleanup/api.nu *
use ./nexus-cleanup/run.nu *
use ./nexus-cleanup/version.nu [VERSION]

def main [
    ...repositories: string             # repositories to clean: proxies, or raw hosted with --allow-hosted
    --config: string                    # read settings from this YAML file; flags override it
    --url: string                       # Nexus base URL (default: $NEXUS_URL)
    --username: string                  # default: $NEXUS_USERNAME
    --password: string                  # default: $NEXUS_PASSWORD
    --pattern: string                   # select proxy repositories by glob instead
    --keep: int                         # newest versions to retain per group (default 1)
    --timeout: duration                 # per-request timeout (default 30sec)
    --max-attempts: int                 # attempts per retryable request (default 4)
    --format: string                    # json or csv (default json)
    --version-scheme: string            # force generic, debian, rpm or date
    --scope-from-path: string           # regex with a (?P<scope>...) group
    --from-path: string                 # regex with (?P<name>...) and (?P<version>...)
    --execute                           # actually delete; omit for a dry run
    --allow-hosted                      # allow named raw hosted repositories; deletes nothing without --execute
    --fail-on-skip                      # exit non-zero if any group was skipped
    --require-cap                       # refuse to run unless a deletion cap is set
    --max-deletions: int                # abort an executing run above this many (default 0 = off)
    --max-deletion-share: float         # abort above this share of components (default 0 = off)
    --summary-out: string               # also write the aggregate here as JSON
    --version                           # print the tool version and exit
] {
    # Before any configuration is read: asking for the version never needs a
    # Nexus, credentials or a valid selection.
    if $version {
        print $VERSION
        return
    }

    # Defaults live only in `config resolve`: a flag left out arrives as null, so a
    # configuration file can supply the value instead.
    let resolved = (try {
        let file = if ($config | is-not-empty) { config load $config } else { null }
        {ok: (config resolve --file $file {
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
            allow_hosted: $allow_hosted
            fail_on_skip: $fail_on_skip
            require_cap: $require_cap
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
