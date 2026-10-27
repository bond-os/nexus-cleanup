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

const COMMON = ["ci/run-configs.sh" "configs/example.yaml" ".editorconfig" ".gitattributes"]

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

# The files `init` writes for these choices, as [{path, content}] with paths
# relative to the target directory. Reads only the templates; writes nothing.
#
# --release-markers is for tools/render-examples.nu alone: `init` never writes
# markers, which mean nothing outside this repository.
export def "scaffold plan" [
    --ci: string                    # gitlab, forgejo, jenkins-docker or jenkins-sh
    --editor: list<string> = []     # vscode and/or intellij
    --env-tool: list<string> = []   # varlock
    --version: string               # the version every pin names
    --release-markers               # mark pinned lines for release-please
]: nothing -> list<record<path: string, content: string>> {
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
    if ($version | is-empty) {
        error make {msg: "scaffold plan: --version is required"}
    }

    let sources = (
        [{area: $"ci/($ci)", path: ($CI_SYSTEMS | get $ci)}]
        | append ($COMMON | each {|p| {area: "common", path: $p} })
        | append ($editor | uniq | each {|e| $EDITORS | get $e | each {|p| {area: $"editors/($e)", path: $p} } } | flatten)
        | append ($env_tool | uniq | each {|e| $ENV_TOOLS | get $e | each {|p| {area: $"env/($e)", path: $p} } } | flatten)
    )
    $sources | each {|s|
        let template = (open --raw ($TEMPLATES | path join $s.area $s.path) | decode utf-8)
        let marked = (if $release_markers { add-markers $s.path $template } else { $template })
        {path: $s.path, content: (render $marked $version)}
    }
}

# Writes a plan into `dir`, creating it and any parent it lacks. Every path is
# checked before anything is written: if any exists, nothing is written and every
# such path is named, unless --force, which overwrites exactly those paths. No other
# file is read, changed or removed. Each written path goes to stderr unless
# --quiet; stdout stays empty. A failure part-way (disk full, permission denied)
# stops and names what was already written, since there is no undoing it.
export def "scaffold write" [
    plan: list<record<path: string, content: string>>
    dir: string
    --force                         # overwrite files that already exist
    --quiet                         # do not list written paths
]: nothing -> nothing {
    # `path type`, not `path exists`: a dangling symlink is still something in the way.
    # It raises when a parent is not a directory; the write then reports why.
    let existing = ($plan | get path | where {|p| (try { $dir | path join $p | path type } catch { null }) != null })
    if ($existing | is-not-empty) and not $force {
        usage-error $"($dir): these files already exist: ($existing | str join ', '). Nothing was written; --force overwrites them and nothing else."
    }

    mut written = []
    for f in $plan {
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
# Returns {help, ci, editors, envs, force, dir}; ci and dir are empty when not given.
export def "scaffold init-args" [args: list<string>]: nothing -> record {
    mut options = {help: false, ci: "", editors: [], envs: [], force: false, dir: ""}
    mut rest = $args
    while ($rest | is-not-empty) {
        let arg = ($rest | first)
        $rest = ($rest | skip 1)
        let split = ($arg | parse --regex '^(?P<flag>--[a-z-]+)=(?P<value>.*)$' | get --optional 0)
        let flag = (if $split != null { $split.flag } else { $arg })
        match $flag {
            "--ci" | "--editor" | "--env" => {
                let value = (if $split != null { $split.value } else if ($rest | is-not-empty) { $rest | first } else { null })
                if $value == null {
                    usage-error $"($flag) needs a value"
                }
                if $split == null { $rest = ($rest | skip 1) }
                match $flag {
                    "--ci" => { $options.ci = $value }
                    "--editor" => { $options.editors = ($options.editors | append $value) }
                    _ => { $options.envs = ($options.envs | append $value) }
                }
            }
            "--force" if $split == null => { $options.force = true }
            "--help" | "-h" => { $options.help = true }
            _ => {
                if ($arg | str starts-with "-") {
                    usage-error $"init does not take ($arg); its options are --ci, --editor, --env and --force"
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
  nexus-cleanup init --ci <system> [--editor <editor>]... [--env <tool>]... [--force] [DIR]

Options:
  --ci <system>      required: (choices $CI_SYSTEMS)
  --editor <editor>  also write schema settings for (choices $EDITORS); repeatable
  --env <tool>       also write files for running locally with (choices $ENV_TOOLS): its schema
                     of the NEXUS_* variables and a .gitignore for its value files; repeatable
  --force            overwrite files init writes that already exist; nothing else is touched
  -h, --help         show this help
"
}

# An image pin: `nexus-cleanup` after a registry path, a quote or whitespace, so that
# GitLab job names such as `nexus-cleanup:dry-run` never match.
const PIN = "(^|[/\"'\\s])nexus-cleanup"

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
    let digest = $"($PIN)\(:[0-9.]+\)?@sha256:[0-9a-f]{64}"
    let had_digest = ($line =~ $digest)
    let moved = (
        $line
        # A digest goes first, keeping an X.Y tag's precision; a tagless one becomes X.Y.Z.
        | str replace --all --regex $"($PIN):[0-9]+\\.[0-9]+@sha256:[0-9a-f]{64}" $"${1}nexus-cleanup:($xy)"
        | str replace --all --regex $digest $"${1}nexus-cleanup:($version)"
        | str replace --all --regex $"($PIN):[0-9]+\\.[0-9]+\\.[0-9]+" $"${1}nexus-cleanup:($version)"
        | str replace --all --regex $"($PIN):[0-9]+\\.[0-9]+\([^.0-9]|$\)" $"${1}nexus-cleanup:($xy)${2}"
        | str replace --all --regex 'NEXUS_CLEANUP_VERSION: v[0-9]+\.[0-9]+\.[0-9]+' $"NEXUS_CLEANUP_VERSION: v($version)"
        | str replace --all --regex 'nexus-cleanup/v[0-9]+\.[0-9]+\.[0-9]+/schema/' $"nexus-cleanup/v($version)/schema/"
    )
    {line: $moved, digest: $had_digest}
}

# Moves every pin `init` writes, in the files of the repository at `dir` that exist, to
# `version`: image tags under any registry, keeping X.Y or X.Y.Z precision; digests,
# replaced by the tag with a warning, since a digest looked up here would be only as
# trustworthy as the tag; the Forgejo release tag; schema addresses; and Forgejo's
# Nushell, copied from this release's own template unless the workflow installs another
# binary than the template's. Writes only files that change and lists them on stderr
# unless --quiet. Returns the changed paths. Reads no other file and makes no request.
export def "scaffold upgrade" [
    dir: string
    --version: string               # the version every pin names afterwards
    --quiet                         # do not list changed paths or warnings
]: nothing -> list<string> {
    if ($version | is-empty) {
        error make {msg: "scaffold upgrade: --version is required"}
    }
    if (try { $dir | path type } catch { null }) != "dir" {
        usage-error $"($dir): not a directory"
    }
    let forgejo = (open --raw ($TEMPLATES | path join "ci" "forgejo" ($CI_SYSTEMS | get forgejo)) | decode utf-8)
    let nu_version = ($forgejo | parse --regex 'NU_VERSION: (\S+)' | get capture0.0)
    let nu_sha256 = ($forgejo | parse --regex 'NU_SHA256: (\S+)' | get capture0.0)
    let note = {|text: string| if not $quiet { print --stderr $text } }

    let candidates = (upgrade-candidates $dir)
    let changes = ($candidates | each {|path|
        let text = (try { open --raw ($dir | path join $path) | decode utf-8 } catch {
            usage-error $"($dir): cannot read ($path)"
        })
        # `split row`, not `lines`: a file's final newline, or its absence, is kept.
        let moved = ($text | split row "\n" | enumerate | each {|l|
            let m = (upgrade-line $l.item $version)
            if $m.digest {
                do $note $"($path):($l.index + 1): digest pin replaced by the tag; re-add a digest once you have verified it"
            }
            $m.line
        } | str join "\n")
        let moved = if not ($moved =~ '(?m)^\s*NU_VERSION: ') {
            $moved
        } else if ($moved =~ 'asset="nu-\$\{NU_VERSION\}-x86_64-unknown-linux-musl"') {
            $moved
            | str replace --regex '(?m)^(\s*NU_VERSION: )\S+' $"${1}($nu_version)"
            | str replace --regex '(?m)^(\s*NU_SHA256: )\S+' $"${1}($nu_sha256)"
        } else {
            do $note $"($path): installs another Nushell binary than the template's; update NU_VERSION and NU_SHA256 by hand"
            $moved
        }
        {path: $path, text: $moved, changed: ($moved != $text)}
    } | where changed)

    for c in $changes {
        try { $c.text | save --force --raw ($dir | path join $c.path) } catch {|e|
            usage-error $"($dir): cannot write ($c.path): ($e.msg? | default 'write failed')"
        }
        do $note $"updated ($c.path)"
    }
    if ($changes | is-empty) {
        if ($candidates | is-empty) {
            do $note $"($dir): none of the files init writes is here; nothing to update"
        } else {
            do $note $"nothing to update: every pin already names ($version)"
        }
    }
    $changes | get path
}

# `upgrade`'s own arguments, parsed by hand for the same reasons as `init`'s.
# Returns {help, dir}; dir is empty when not given.
export def "scaffold upgrade-args" [args: list<string>]: nothing -> record {
    mut options = {help: false, dir: ""}
    for arg in $args {
        if $arg in ["--help" "-h"] {
            $options.help = true
        } else if ($arg | str starts-with "-") {
            usage-error $"upgrade does not take ($arg); its only option is --help"
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
  nexus-cleanup upgrade [DIR]

Options:
  -h, --help         show this help
"
}
