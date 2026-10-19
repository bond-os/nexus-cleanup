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

# Duration spellings `into duration` accepts — `30sec`, `1.5min`, `1hr 30min`, `1_000ms` —
# written loosely enough to admit every one of them: the schema may be looser than the
# tool, never stricter.
export const DURATION_PATTERN = '^\s*[-+]?[0-9.][0-9_.eE+-]*\s*(?:ns|us|µs|ms|sec|min|hr|day|wk)(?:\s*[-+]?[0-9.][0-9_.eE+-]*\s*(?:ns|us|µs|ms|sec|min|hr|day|wk))*\s*$'

# One row per configuration-file key: its flag spelling, the setting it fills, its
# type, the JSON Schema constraints it adds, and the description editors show.
# Mapping, type checks, the schema and the README table all derive from this.
export const CONFIG_KEYS = [
    {key: "url", field: "url", type: "string",
        schema: {pattern: "^http", not: {pattern: "^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*@"}},
        description: "Nexus base URL; NEXUS_URL and --url override it. Never with credentials in it."}
    {key: "username", field: "username", type: "string", schema: {},
        description: "Nexus username; NEXUS_USERNAME and --username override it."}
    {key: "repositories", field: "repositories", type: "list<string>", schema: {},
        description: "Proxy repositories to clean, by name."}
    {key: "pattern", field: "pattern", type: "string", schema: {},
        description: "Select proxy repositories by glob instead of by name."}
    {key: "keep", field: "keep", type: "int", schema: {minimum: 1},
        description: "Newest versions to retain per group (default 1)."}
    {key: "timeout", field: "timeout", type: "duration", schema: {pattern: $DURATION_PATTERN},
        description: "Per-request timeout, such as 30sec or 2min (default 30sec)."}
    {key: "max-attempts", field: "max_attempts", type: "int", schema: {minimum: 1},
        description: "Attempts per retryable request (default 4)."}
    {key: "format", field: "format", type: "string", schema: {enum: $FORMATS},
        description: "Report format: json or csv (default json)."}
    {key: "version-scheme", field: "version_scheme", type: "string", schema: {enum: ["" ...$SCHEMES]},
        description: "Force a version scheme instead of the per-format default."}
    {key: "scope-from-path", field: "scope_pattern", type: "string",
        schema: {pattern: '^$|\(\?P<scope>'},
        description: "Regex with a (?P<scope>...) group naming the scope within the asset path."}
    {key: "from-path", field: "from_path", type: "string",
        schema: {pattern: '^$|^(?=[\s\S]*\(\?P<name>)(?=[\s\S]*\(\?P<version>)'},
        description: "Regex with (?P<name>...) and (?P<version>...) groups: retain by path."}
    {key: "fail-on-skip", field: "fail_on_skip", type: "bool", schema: {},
        description: "Exit non-zero if any group was skipped."}
    {key: "max-deletions", field: "max_deletions", type: "int", schema: {minimum: 0},
        description: "Abort an executing run above this many deletions (0 = off)."}
    {key: "max-deletion-share", field: "max_deletion_share", type: "number", schema: {minimum: 0, maximum: 1},
        description: "Abort above this share of enumerated components (0 = off)."}
    {key: "summary-out", field: "summary_out", type: "string", schema: {},
        description: "Also write the aggregate here as JSON, relative to the working directory."}
]

# Keys a file may never set, each with the reason given to the operator.
export const REFUSED_KEYS = [
    {key: "execute", description: "Deletion is requested only by the --execute flag, never by a configuration file."}
    {key: "password", description: "Credentials never belong in a configuration file; set NEXUS_PASSWORD or pass --password."}
]

# The key a file may use to name its own JSON Schema; read and ignored.
export const SCHEMA_KEY = "$schema"

def usage-error [message: string] {
    error make {msg: $"usage: ($message)"}
}

def has-type [value: any, type: string]: nothing -> bool {
    let actual = ($value | describe)
    match $type {
        "list<string>" => (($actual | str starts-with "list") and ($value | all {|x| ($x | describe) == "string" }))
        "number" => ($actual in ["int" "float"])
        "duration" => ($actual == "string")
        _ => ($actual == $type)
    }
}

def type-name [type: string]: nothing -> string {
    match $type {
        "int" => "an integer"
        "number" => "a number"
        "bool" => "true or false"
        "list<string>" => "a list of names"
        "duration" => "a duration such as 30sec"
        _ => "text"
    }
}

# Read a configuration file into settings keyed like `config resolve` overrides.
# Only what is specific to the file is checked here — parsing, refused and unknown
# keys, types; ranges and patterns are validated with every other source in
# `config resolve`. Returns {path, values}.
export def "config load" [path: string]: nothing -> record {
    if not ($path | path exists) {
        usage-error $"($path): configuration file not found"
    }
    let text = (try { open --raw $path | decode utf-8 } catch {
        usage-error $"($path): configuration file cannot be read"
    })
    let doc = (try { $text | from yaml } catch {
        usage-error $"($path): not valid YAML"
    })
    let doc = if $doc == null { {} } else { $doc }
    if not (($doc | describe) | str starts-with "record") {
        usage-error $"($path): the file must contain a mapping of settings at the top level"
    }

    let keys = ($doc | columns)
    for refused in $REFUSED_KEYS {
        if $refused.key in $keys {
            usage-error $"($path): '($refused.key)' is not allowed in a configuration file. ($refused.description)"
        }
    }
    let known = ($CONFIG_KEYS | get key | append $SCHEMA_KEY)
    let unknown = ($keys | where {|k| $k not-in $known })
    if ($unknown | is-not-empty) {
        usage-error $"($path): unknown key ($unknown | each {|k| $"'($k)'" } | str join ', '); expected one of ($CONFIG_KEYS | get key | str join ', ')"
    }

    if $SCHEMA_KEY in $keys and (($doc | get $SCHEMA_KEY | describe) != "string") {
        usage-error $"($path): '($SCHEMA_KEY)' must be text, the address of the schema"
    }

    mut values = {}
    for row in $CONFIG_KEYS {
        if $row.key not-in $keys { continue }
        let value = ($doc | get $row.key)
        if not (has-type $value $row.type) {
            usage-error $"($path): '($row.key)' must be (type-name $row.type)"
        }
        let value = match $row.type {
            "duration" => (try { $value | into duration } catch {
                usage-error $"($path): '($row.key)' must be (type-name $row.type), got '($value)'"
            })
            "number" => ($value | into float)
            _ => $value
        }
        if $row.key == "url" and ($value =~ '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*@') {
            usage-error $"($path): 'url' must not carry credentials; set NEXUS_USERNAME and NEXUS_PASSWORD instead"
        }
        $values = ($values | insert $row.field $value)
    }

    {path: $path, values: $values}
}

def env-or [name: string, override: any]: nothing -> string {
    if ($override != null) and (($override | into string) | is-not-empty) {
        return ($override | into string)
    }
    $env | get --optional $name | default ""
}

def given [value: any]: nothing -> bool {
    ($value != null) and (($value | describe) != "string" or ($value | is-not-empty))
}

# The value of one setting and where it came from: the flag when given, else the
# file, else the default.
def layer [overrides: record, file_values: record, field: string, fallback: any]: nothing -> record {
    let flag = ($overrides | get --optional $field)
    if (given $flag) { return {value: $flag, from: "flag"} }
    let from_file = ($file_values | get --optional $field)
    if (given $from_file) { return {value: $from_file, from: "file"} }
    {value: $fallback, from: "default"}
}

# How a setting is named in a message: as the flag the operator typed, or as the key
# in the file they wrote.
def label [field: string, from: string, path: string]: nothing -> string {
    let key = ($CONFIG_KEYS | where field == $field | get --optional 0.key | default $field)
    if $from == "file" { $"'($key)' in ($path)" } else { $"--($key)" }
}

def note [message: string] {
    print --stderr $"nexus-cleanup: ($message)"
}

# Resolve configuration from flags, the environment and an optional configuration
# file (the output of `config load`). A flag overrides the file; for the URL and
# username the environment sits between them. Raises a usage error naming the
# offending setting by the source it came from.
export def "config resolve" [
    overrides: record = {}
    --file: record                      # output of `config load`
]: nothing -> record {
    let file_values = ($file.values? | default {})
    let path = ($file.path? | default "")

    # url: flag > NEXUS_URL > file
    let url_flag = ($overrides.url? | default null)
    let url_env = ($env.NEXUS_URL? | default "")
    let url_file = ($file_values.url? | default "")
    let url = if (given $url_flag) {
        {value: ($url_flag | into string), name: "--url"}
    } else if ($url_env | is-not-empty) {
        {value: $url_env, name: "NEXUS_URL"}
    } else if ($url_file | is-not-empty) {
        {value: $url_file, name: $"'url' in ($path)"}
    } else {
        usage-error "NEXUS_URL is not set and no --url was given"
    }
    if ($url_file | is-not-empty) and $url.name != $"'url' in ($path)" {
        note $"the url in ($path) is overridden by ($url.name)"
    }
    if not ($url.value | str starts-with "http") {
        usage-error $"($url.name) must be an http or https URL, got '($url.value)'"
    }

    let username_flag = ($overrides.username? | default null)
    let username = if (given $username_flag) {
        $username_flag | into string
    } else if (($env.NEXUS_USERNAME? | default "") | is-not-empty) {
        $env.NEXUS_USERNAME
    } else {
        $file_values.username? | default ""
    }

    let keep = (layer $overrides $file_values "keep" 1)
    if $keep.value < 1 { usage-error $"(label "keep" $keep.from $path) must be at least 1, got ($keep.value)" }

    let timeout = (layer $overrides $file_values "timeout" 30sec)
    if $timeout.value <= 0sec { usage-error $"(label "timeout" $timeout.from $path) must be positive, got ($timeout.value)" }

    let max_attempts = (layer $overrides $file_values "max_attempts" 4)
    if $max_attempts.value < 1 { usage-error $"(label "max_attempts" $max_attempts.from $path) must be at least 1, got ($max_attempts.value)" }

    let format = (layer $overrides $file_values "format" "json")
    if $format.value not-in $FORMATS {
        usage-error $"(label "format" $format.from $path) must be one of ($FORMATS | str join ', '), got '($format.value)'"
    }

    let version_scheme = (layer $overrides $file_values "version_scheme" "")
    if ($version_scheme.value | is-not-empty) and ($version_scheme.value not-in $SCHEMES) {
        usage-error $"(label "version_scheme" $version_scheme.from $path) must be one of ($SCHEMES | str join ', '), got '($version_scheme.value)'"
    }

    let scope_pattern = (layer $overrides $file_values "scope_pattern" "")
    if ($scope_pattern.value | is-not-empty) {
        let name = (label "scope_pattern" $scope_pattern.from $path)
        if not ($scope_pattern.value | str contains "(?P<scope>") {
            usage-error $"($name) must contain a named group \(?P<scope>...\)"
        }
        let compiles = (try { "probe" | parse --regex $scope_pattern.value; true } catch { false })
        if not $compiles {
            usage-error $"($name) is not a valid expression: '($scope_pattern.value)'"
        }
    }

    let from_path = (layer $overrides $file_values "from_path" "")
    if ($from_path.value | is-not-empty) {
        let name = (label "from_path" $from_path.from $path)
        if not (($from_path.value | str contains "(?P<name>") and ($from_path.value | str contains "(?P<version>")) {
            usage-error $"($name) must contain both \(?P<name>...\) and \(?P<version>...\) groups"
        }
        let compiles = (try { "probe" | parse --regex $from_path.value; true } catch { false })
        if not $compiles {
            usage-error $"($name) is not a valid expression: '($from_path.value)'"
        }
    }

    # The selection is one unit: whatever the command line selects replaces the
    # file's names and pattern together.
    let cli_repositories = ($overrides.repositories? | default [])
    let cli_pattern = ($overrides.pattern? | default "")
    let selection = if ($cli_repositories | is-not-empty) or ($cli_pattern | is-not-empty) {
        {repositories: $cli_repositories, pattern: $cli_pattern}
    } else {
        {repositories: ($file_values.repositories? | default []), pattern: ($file_values.pattern? | default "")}
    }
    if ($selection.repositories | is-empty) and ($selection.pattern | is-empty) {
        usage-error "name at least one repository, or supply --pattern"
    }

    let max_deletions = (layer $overrides $file_values "max_deletions" 0)
    if $max_deletions.value < 0 {
        usage-error $"(label "max_deletions" $max_deletions.from $path) cannot be negative, got ($max_deletions.value)"
    }

    let max_deletion_share = (layer $overrides $file_values "max_deletion_share" 0.0)
    if $max_deletion_share.value < 0.0 or $max_deletion_share.value > 1.0 {
        usage-error $"(label "max_deletion_share" $max_deletion_share.from $path) must be between 0 and 1, got ($max_deletion_share.value)"
    }

    # A flag only: the guard belongs to the pipeline. Checked for dry runs too, so a
    # file missing its cap fails in the scheduled dry run, not at execution.
    if ($overrides.require_cap? | default false) and $max_deletions.value == 0 and $max_deletion_share.value == 0.0 {
        let where = if ($path | is-not-empty) { $" in ($path) or" } else { "" }
        usage-error $"--require-cap: set max-deletions or max-deletion-share($where) pass --max-deletions or --max-deletion-share"
    }

    {
        url: ($url.value | str trim --right --char "/")
        username: $username
        # Never from the file: `config load` refuses a password key.
        password: (env-or "NEXUS_PASSWORD" ($overrides.password? | default null))
        repositories: $selection.repositories
        pattern: $selection.pattern
        keep: $keep.value
        timeout: $timeout.value
        max_attempts: $max_attempts.value
        format: $format.value
        version_scheme: $version_scheme.value
        scope_pattern: $scope_pattern.value
        from_path: $from_path.value
        # Never from the file: only the flag asks for deletion.
        execute: ($overrides.execute? | default false)
        fail_on_skip: (($overrides.fail_on_skip? | default false) or ($file_values.fail_on_skip? | default false))
        max_deletions: $max_deletions.value
        max_deletion_share: $max_deletion_share.value
        summary_out: (layer $overrides $file_values "summary_out" "" | get value)
        config_file: $path
    }
}
