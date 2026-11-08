# Repository initialisation: renders the files `init` writes from ./templates and
# writes them into a directory without overwriting anything unasked.
#
# Templates are whole files stored at the path they are written to, below the
# area that selects them: common/ always, ci/<system>/ for the chosen CI system,
# editors/<editor>/ for each chosen editor, env/<tool>/ for each chosen environment
# tool. Rendering replaces three placeholders and nothing else, so each template
# reads as the file it becomes.

# Located from this file at parse time, so it holds from any working directory.
const TEMPLATES = path self templates

# The pipeline each CI system reads, at the path it reads it from.
export const CI_SYSTEMS = {
    gitlab: ".gitlab-ci.yml"
    forgejo: ".forgejo/workflows/nexus-cleanup.yml"
    jenkins-docker: "Jenkinsfile"
    jenkins-sh: "Jenkinsfile"
}

export const EDITORS = {
    vscode: [".vscode/settings.json" ".vscode/extensions.json"]
    intellij: [".idea/jsonSchemas.xml"]
}

# Environment tools for local runs. Never used by a generated pipeline.
export const ENV_TOOLS = {
    varlock: [".env.schema" ".gitignore"]
}

const COMMON = [
    {path: "ci/run-configs.sh", group: "runner"}
    {path: "configs/example.yaml", group: "example"}
    {path: ".editorconfig", group: "base"}
    {path: ".gitattributes", group: "base"}
]

# What --only can name. Groups follow what is safe to overwrite, not what a file is
# about: the pipeline holds the operator's edits, so run-configs.sh, which it calls,
# is a group of its own.
export const GROUPS = ["pipeline" "runner" "base" "example" "editor" "env"]

const MARKER = "x-release-please-version"

def usage-error [message: string] {
    error make {msg: $"usage: ($message)"}
}

def choices [record: record]: nothing -> string { $record | columns | str join ", " }

# The comment that carries a release marker in a file of this kind.
def marker-comment [path: string, text: string]: nothing -> string {
    let name = ($path | path basename)
    if ($name | str ends-with ".xml") {
        $"<!-- ($text) -->"
    } else if ($name == "Jenkinsfile") or ($name | str ends-with ".json") {
        $"// ($text)"
    } else {
        $"# ($text)"
    }
}

# Marks every template line holding a placeholder, so that release-please moves the
# pin it becomes. A modeline must stay exactly one URL, so it is wrapped in block
# markers on lines of their own; every other line takes the marker inline.
def add-markers [path: string, template: string]: nothing -> string {
    # `split row`, not `lines`: a template's final newline, or its absence, is kept.
    $template | split row "\n" | each {|line|
        if not ($line =~ '\{\{(version|image|schema_url)\}\}') {
            $line
        } else if ($line | str starts-with "# yaml-language-server:") {
            ["# x-release-please-start-version" $line "# x-release-please-end"] | str join "\n"
        } else {
            $"($line) (marker-comment $path $MARKER)"
        }
    } | str join "\n"
}

def render [template: string, version: string]: nothing -> string {
    let image = $"ghcr.io/bond-os/nexus-cleanup:($version)"
    let schema_url = $"https://raw.githubusercontent.com/bond-os/nexus-cleanup/v($version)/schema/config.schema.json"
    $template
    | str replace --all "{{image}}" $image
    | str replace --all "{{schema_url}}" $schema_url
    | str replace --all "{{version}}" $version
}

# The files `init` writes for these choices, as [{path, group, content}] with paths
# relative to the target directory. Reads only the templates; writes nothing.
#
# --only narrows the choices to the named groups; it never adds to them, so a group
# the choices leave empty is a usage error rather than a run that writes nothing.
#
# --release-markers is for tools/render-examples.nu alone: `init` never writes
# markers, which mean nothing outside this repository.
export def "scaffold plan" [
    --ci: string                    # gitlab, forgejo, jenkins-docker or jenkins-sh
    --editor: list<string> = []     # vscode and/or intellij
    --env-tool: list<string> = []   # varlock
    --only: list<string> = []       # keep only these groups; all of them when empty
    --version: string               # the version every pin names
    --release-markers               # mark pinned lines for release-please
]: nothing -> list<record<path: string, group: string, content: string>> {
    if ($ci | is-empty) {
        usage-error $"--ci is required: one of (choices $CI_SYSTEMS)"
    }
    if not ($ci in $CI_SYSTEMS) {
        usage-error $"unknown CI system '($ci)': choose one of (choices $CI_SYSTEMS)"
    }
    for e in $editor {
        if not ($e in $EDITORS) {
            usage-error $"unknown editor '($e)': choose from (choices $EDITORS)"
        }
    }
    for e in $env_tool {
        if not ($e in $ENV_TOOLS) {
            usage-error $"unknown environment tool '($e)': choose from (choices $ENV_TOOLS)"
        }
    }
    for g in $only {
        if not ($g in $GROUPS) {
            usage-error $"unknown group '($g)': choose from ($GROUPS | str join ', ')"
        }
    }
    if ($version | is-empty) {
        error make {msg: "scaffold plan: --version is required"}
    }

    let sources = (
        [{area: $"ci/($ci)", path: ($CI_SYSTEMS | get $ci), group: "pipeline"}]
        | append ($COMMON | each {|c| {area: "common", path: $c.path, group: $c.group} })
        | append ($editor | uniq | each {|e| $EDITORS | get $e | each {|p| {area: $"editors/($e)", path: $p, group: "editor"} } } | flatten)
        | append ($env_tool | uniq | each {|e| $ENV_TOOLS | get $e | each {|p| {area: $"env/($e)", path: $p, group: "env"} } } | flatten)
    )
    for g in $only {
        if not ($g in ($sources | get group)) {
            usage-error $"--only ($g) selects no file: choose what it should narrow with --($g)"
        }
    }
    let selected = (if ($only | is-empty) { $sources } else { $sources | where {|s| $s.group in $only } })
    $selected | each {|s|
        let template = (open --raw ($TEMPLATES | path join $s.area $s.path) | decode utf-8)
        let marked = (if $release_markers { add-markers $s.path $template } else { $template })
        {path: $s.path, group: $s.group, content: (render $marked $version)}
    }
}

# Whether a planned file is absent, matches its plan or differs from it.
def file-state [dir: string, file: record]: nothing -> string {
    let target = ($dir | path join $file.path)
    # `path type`, not `path exists`: a dangling symlink is still something in the way.
    # It raises when a parent is not a directory; the write then reports why.
    if (try { $target | path type } catch { null }) == null {
        return "new"
    }
    # A directory or an unreadable file in the way cannot match.
    let same = (try { (open --raw $target | decode utf-8) == $file.content } catch { false })
    if $same { "identical" } else { "differs" }
}

# What this mode does with each planned file, as the plan's records with `state` and
# `action` added: the one decision, so that --check reports what a run does. Without
# --force or --skip-existing one existing file refuses the whole plan, so every
# action is then `refuse`, for the files that are new as well.
def decide [
    plan: list
    dir: string
    --force
    --skip-existing
]: nothing -> list {
    if $force and $skip_existing {
        usage-error "--force and --skip-existing cannot be combined: one overwrites what exists, the other keeps it"
    }
    let states = ($plan | each {|f| $f | insert state (file-state $dir $f) })
    let refused = (not $force) and (not $skip_existing) and ($states | any {|f| $f.state != "new" })
    $states | each {|f|
        let action = (if $refused {
            "refuse"
        } else if $f.state == "new" {
            "write"
        } else if $force {
            "overwrite"
        } else {
            "skip"
        })
        $f | insert action $action
    }
}

# What `scaffold write` would do with a plan in `dir`, one line per file: state, action,
# group and path. Reads the planned files that exist; writes and creates nothing.
export def "scaffold check" [
    plan: list<record<path: string, group: string, content: string>>
    dir: string
    --force                         # as `scaffold write`
    --skip-existing                 # as `scaffold write`
]: nothing -> string {
    decide $plan $dir --force=$force --skip-existing=$skip_existing
    | each {|d|
        [($d.state | fill --width 9) ($d.action | fill --width 9) ($d.group | fill --width 8) $d.path] | str join " "
    }
    | str join "\n"
}

# Writes a plan into `dir`, creating it and any parent it lacks. Every path is
# checked before anything is written: if any exists, nothing is written and every
# such path is named, unless --force, which overwrites exactly those paths, or
# --skip-existing, which keeps them and names them. No other file is read, changed or
# removed. Each written path goes to stderr unless --quiet; stdout stays empty. A
# failure part-way (disk full, permission denied) stops and names what was already
# written, since there is no undoing it.
export def "scaffold write" [
    plan: list<record<path: string, group: string, content: string>>
    dir: string
    --force                         # overwrite files that already exist
    --skip-existing                 # keep files that already exist and write the rest
    --quiet                         # do not list written or kept paths
]: nothing -> nothing {
    let decisions = (decide $plan $dir --force=$force --skip-existing=$skip_existing)
    if ($decisions | any {|d| $d.action == "refuse" }) {
        let existing = ($decisions | where state != "new" | get path)
        usage-error $"($dir): these files already exist: ($existing | str join ', '). Nothing was written; --force overwrites them and nothing else, --skip-existing keeps them and writes the rest."
    }

    mut written = []
    for f in $decisions {
        if $f.action == "skip" {
            if not $quiet { print --stderr $"kept ($f.path): it already exists" }
            continue
        }
        let target = ($dir | path join $f.path)
        let failure = (try {
            mkdir ($target | path dirname)
            $f.content | save --force --raw $target
            null
        } catch {|e| $e.msg? | default "write failed" })
        if $failure != null {
            let done = (if ($written | is-empty) { "none" } else { $written | str join ", " })
            usage-error $"($dir): cannot write ($f.path): ($failure). Files already written: ($done)."
        }
        if not $quiet { print --stderr $"wrote ($f.path)" }
        $written = ($written | append $f.path)
    }
}

# `init`'s own arguments. Parsed by hand because Nushell keeps only the last of a
# repeated flag (--editor is repeatable) and exits 1, not with the usage code, on
# an unknown one such as a cleanup run's --execute.
# Returns {help, ci, editors, envs, only, force, skip_existing, check, dir}; ci and dir
# are empty when not given.
export def "scaffold init-args" [args: list<string>]: nothing -> record {
    mut options = {help: false, ci: "", editors: [], envs: [], only: [], force: false, skip_existing: false, check: false, dir: ""}
    mut rest = $args
    while ($rest | is-not-empty) {
        let arg = ($rest | first)
        $rest = ($rest | skip 1)
        let split = ($arg | parse --regex '^(?P<flag>--[a-z-]+)=(?P<value>.*)$' | get --optional 0)
        let flag = (if $split != null { $split.flag } else { $arg })
        match $flag {
            "--ci" | "--editor" | "--env" | "--only" => {
                let value = (if $split != null { $split.value } else if ($rest | is-not-empty) { $rest | first } else { null })
                if $value == null {
                    usage-error $"($flag) needs a value"
                }
                if $split == null { $rest = ($rest | skip 1) }
                match $flag {
                    "--ci" => { $options.ci = $value }
                    "--editor" => { $options.editors = ($options.editors | append $value) }
                    "--only" => { $options.only = ($options.only | append $value) }
                    _ => { $options.envs = ($options.envs | append $value) }
                }
            }
            "--force" if $split == null => { $options.force = true }
            "--skip-existing" if $split == null => { $options.skip_existing = true }
            "--check" if $split == null => { $options.check = true }
            "--help" | "-h" => { $options.help = true }
            _ => {
                if ($arg | str starts-with "-") {
                    usage-error $"init does not take ($arg); its options are --ci, --editor, --env, --only, --force, --skip-existing and --check"
                }
                if ($options.dir | is-not-empty) {
                    usage-error $"init takes one target directory, not '($options.dir)' and '($arg)'"
                }
                $options.dir = $arg
            }
        }
    }
    $options
}

# Help for `init`, which, being parsed by hand, has no generated --help.
export def "scaffold init-help" [version: string]: nothing -> string {
    $"Write a configuration repository for nexus-cleanup into DIR, the working directory
by default: the pipeline, ci/run-configs.sh, configs/example.yaml, .editorconfig and
.gitattributes, with every version pinned to ($version). Needs no Nexus and no credentials.

Usage:
  nexus-cleanup init --ci <system> [--editor <editor>]... [--env <tool>]... [--only <group>]...
                     [--force | --skip-existing] [--check] [DIR]

Options:
  --ci <system>      required: (choices $CI_SYSTEMS)
  --editor <editor>  also write schema settings for (choices $EDITORS); repeatable
  --env <tool>       also write files for running locally with (choices $ENV_TOOLS): its schema
                     of the NEXUS_* variables and a .gitignore for its value files; repeatable
  --only <group>     act only on these groups of the files chosen above: ($GROUPS | str join ', ');
                     repeatable. With --force, `example` replaces a real configuration kept in
                     configs/example.yaml and `env` replaces your own .gitignore
  --force            overwrite files init writes that already exist; nothing else is touched
  --skip-existing    keep files that already exist and write the rest
  --check            write nothing; print what this command would do with each file
  -h, --help         show this help
"
}

# The Nushell release the Forgejo template of this tool installs.
def forgejo-nushell []: nothing -> record<version: string, sha256: string> {
    let forgejo = (open --raw ($TEMPLATES | path join "ci" "forgejo" ($CI_SYSTEMS | get forgejo)) | decode utf-8)
    {
        version: ($forgejo | parse --regex 'NU_VERSION: (\S+)' | get capture0.0)
        sha256: ($forgejo | parse --regex 'NU_SHA256: (\S+)' | get capture0.0)
    }
}

# An image pin: `nexus-cleanup` after a registry path, a quote or whitespace, so that
# GitLab job names such as `nexus-cleanup:dry-run` never match.
const PIN = "(^|[/\"'\\s])nexus-cleanup"

# An image pin by digest, with or without a tag.
const DIGEST_PIN = $"($PIN)\(:[0-9.]+\)?@sha256:[0-9a-f]{64}"

# The files `upgrade` may change, relative to `dir`, that exist there: the pipelines and
# editor files `init` writes, and every configuration file.
def upgrade-candidates [dir: string]: nothing -> list<string> {
    let written = ($CI_SYSTEMS | values | append ($EDITORS | values | flatten) | uniq)
    let root = ($dir | path expand)
    let configs = (glob ($root | path join "configs" "*.{yaml,yml}") --no-dir | path relative-to $root)
    $written | where {|p| ($dir | path join $p | path type) == "file" } | append $configs | uniq | sort
}

# One line with its pins moved to `version`; returns the line and whether a digest went.
def upgrade-line [line: string, version: string]: nothing -> record<line: string, digest: bool> {
    let xy = ($version | split row "." | first 2 | str join ".")
    let had_digest = ($line =~ $DIGEST_PIN)
    let moved = (
        $line
        # A digest goes first, keeping an X.Y tag's precision; a tagless one becomes X.Y.Z.
        | str replace --all --regex $"($PIN):[0-9]+\\.[0-9]+@sha256:[0-9a-f]{64}" $"${1}nexus-cleanup:($xy)"
        | str replace --all --regex $DIGEST_PIN $"${1}nexus-cleanup:($version)"
        | str replace --all --regex $"($PIN):[0-9]+\\.[0-9]+\\.[0-9]+" $"${1}nexus-cleanup:($version)"
        | str replace --all --regex $"($PIN):[0-9]+\\.[0-9]+\([^.0-9]|$\)" $"${1}nexus-cleanup:($xy)${2}"
        | str replace --all --regex 'NEXUS_CLEANUP_VERSION: v[0-9]+\.[0-9]+\.[0-9]+' $"NEXUS_CLEANUP_VERSION: v($version)"
        | str replace --all --regex 'nexus-cleanup/v[0-9]+\.[0-9]+\.[0-9]+/schema/' $"nexus-cleanup/v($version)/schema/"
    )
    {line: $moved, digest: $had_digest}
}

# A file's text with every pin moved to `version`. `note` receives what the operator
# should be told about the file.
def move-pins [path: string, text: string, version: string, nushell: record, note: closure]: nothing -> string {
    # `split row`, not `lines`: a file's final newline, or its absence, is kept.
    let moved = ($text | split row "\n" | enumerate | each {|l|
        let m = (upgrade-line $l.item $version)
        if $m.digest {
            do $note $"($path):($l.index + 1): digest pin replaced by the tag; re-add a digest once you have verified it"
        }
        $m.line
    } | str join "\n")
    if not ($moved =~ '(?m)^\s*NU_VERSION: ') {
        $moved
    } else if ($moved =~ 'asset="nu-\$\{NU_VERSION\}-x86_64-unknown-linux-musl"') {
        $moved
        | str replace --regex '(?m)^(\s*NU_VERSION: )\S+' $"${1}($nushell.version)"
        | str replace --regex '(?m)^(\s*NU_SHA256: )\S+' $"${1}($nushell.sha256)"
    } else {
        do $note $"($path): installs another Nushell binary than the template's; update NU_VERSION and NU_SHA256 by hand"
        $moved
    }
}

# The files of the repository at `dir` that `upgrade` handles and that pin another
# version than `version`. Losing a digest is what `upgrade` does to every digest pin, not
# a sign that the pin is stale, so the comparison leaves digests out. Reads those files
# only and raises nothing: this only decides whether to warn.
export def "scaffold stale-pins" [dir: string, --version: string]: nothing -> list<string> {
    let nushell = (forgejo-nushell)
    let candidates = (try { upgrade-candidates $dir } catch { [] })
    $candidates | where {|path|
        try {
            let text = (
                open --raw ($dir | path join $path) | decode utf-8
                | str replace --all --regex $DIGEST_PIN "${1}nexus-cleanup${2}"
            )
            (move-pins $path $text $version $nushell {|_| }) != $text
        } catch { false }
    }
}

# Moves every pin `init` writes, in the files of the repository at `dir` that exist, to
# `version`: image tags under any registry, keeping X.Y or X.Y.Z precision; digests,
# replaced by the tag with a warning, since a digest looked up here would be only as
# trustworthy as the tag; the Forgejo release tag; schema addresses; and Forgejo's
# Nushell, copied from this release's own template unless the workflow installs another
# binary than the template's. Writes only files that change and lists them on stderr
# unless --quiet. Returns the changed paths. Reads no other file and makes no request.
# With --check nothing is written: the warnings stand and the paths returned are those
# it would change.
export def "scaffold upgrade" [
    dir: string
    --version: string               # the version every pin names afterwards
    --check                         # write nothing
    --quiet                         # do not list changed paths or warnings
]: nothing -> list<string> {
    if ($version | is-empty) {
        error make {msg: "scaffold upgrade: --version is required"}
    }
    if (try { $dir | path type } catch { null }) != "dir" {
        usage-error $"($dir): not a directory"
    }
    let nushell = (forgejo-nushell)
    let note = {|text: string| if not $quiet { print --stderr $text } }

    let candidates = (upgrade-candidates $dir)
    let changes = ($candidates | each {|path|
        let text = (try { open --raw ($dir | path join $path) | decode utf-8 } catch {
            usage-error $"($dir): cannot read ($path)"
        })
        let moved = (move-pins $path $text $version $nushell $note)
        {path: $path, text: $moved, changed: ($moved != $text)}
    } | where changed)

    if not $check {
        for c in $changes {
            try { $c.text | save --force --raw ($dir | path join $c.path) } catch {|e|
                usage-error $"($dir): cannot write ($c.path): ($e.msg? | default 'write failed')"
            }
            do $note $"updated ($c.path)"
        }
    }
    if ($changes | is-empty) {
        if ($candidates | is-empty) {
            do $note $"($dir): none of the files init writes is here; nothing to update"
        } else if $check {
            do $note $"nothing would change: every pin already names ($version)"
        } else {
            do $note $"nothing to update: every pin already names ($version)"
        }
    }
    $changes | get path
}

# `upgrade`'s own arguments, parsed by hand for the same reasons as `init`'s.
# Returns {help, check, dir}; dir is empty when not given.
export def "scaffold upgrade-args" [args: list<string>]: nothing -> record {
    mut options = {help: false, check: false, dir: ""}
    for arg in $args {
        if $arg in ["--help" "-h"] {
            $options.help = true
        } else if $arg == "--check" {
            $options.check = true
        } else if ($arg | str starts-with "-") {
            usage-error $"upgrade does not take ($arg); its options are --check and --help"
        } else if ($options.dir | is-not-empty) {
            usage-error $"upgrade takes one directory, not '($options.dir)' and '($arg)'"
        } else {
            $options.dir = $arg
        }
    }
    $options
}

# Help for `upgrade`, parsed by hand like `init`.
export def "scaffold upgrade-help" [version: string]: nothing -> string {
    $"Move every version pin `init` writes, in the configuration repository in DIR, the
working directory by default, to ($version): the pipeline's image tag \(or Forgejo's
release tag and Nushell\), and the schema address in configs/ and the editor settings.
Image pins keep their X.Y or X.Y.Z precision; a digest pin becomes the tag, with a
warning. Lists each file it changed. Needs no Nexus and no credentials.

Usage:
  nexus-cleanup upgrade [--check] [DIR]

Options:
  --check            write nothing; print each file this command would change
  -h, --help         show this help
"
}
