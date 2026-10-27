use ./harness.nu *
use ../nexus-cleanup/scaffold.nu *
use ../nexus-cleanup/config.nu *
use ../nexus-cleanup/api.nu *
use ../nexus-cleanup/run.nu *

const PIPELINES = {
    gitlab: ".gitlab-ci.yml"
    forgejo: ".forgejo/workflows/nexus-cleanup.yml"
    jenkins-docker: "Jenkinsfile"
    jenkins-sh: "Jenkinsfile"
}
const COMMON = ["ci/run-configs.sh" "configs/example.yaml" ".editorconfig" ".gitattributes"]
const SCHEMA_030 = "https://raw.githubusercontent.com/bond-os/nexus-cleanup/v0.3.0/schema/config.schema.json"

def paths [plan: list]: nothing -> list<string> { $plan | get path | sort }

def file [plan: list, path: string]: nothing -> string {
    $plan | where path == $path | get content.0
}

# The error raised by a closure, or null when it returns.
def raised [action: closure]: nothing -> any {
    try { do $action; null } catch {|e| $e }
}

def assert-usage [err: any, ...needles: string] {
    assert not equal $err null "no error was raised"
    assert ($err.msg | str starts-with "usage:") $"not a usage error: ($err.msg)"
    for n in $needles {
        assert ($err.msg | str contains $n) $"'($n)' missing from: ($err.msg)"
    }
}

run-suite "scaffold plan" [
    { name: "each CI system plans its pipeline, the loop, the example and the two dotfiles", run: {||
        for ci in ($PIPELINES | columns) {
            let plan = (scaffold plan --ci $ci --version "0.3.0")
            assert equal (paths $plan) ($COMMON | append ($PIPELINES | get $ci) | sort) $ci
        }
    } }
    { name: "editors add their own files and nothing by default", run: {||
        let base = (paths (scaffold plan --ci gitlab --version "0.3.0"))
        assert not ($base | any {|p| ($p | str starts-with ".vscode/") or ($p | str starts-with ".idea/") })
        let vscode = (paths (scaffold plan --ci gitlab --editor [vscode] --version "0.3.0"))
        assert equal $vscode ($base | append [".vscode/settings.json" ".vscode/extensions.json"] | sort)
        let idea = (paths (scaffold plan --ci gitlab --editor [intellij] --version "0.3.0"))
        assert equal $idea ($base | append ".idea/jsonSchemas.xml" | sort)
        let both = (paths (scaffold plan --ci gitlab --editor [vscode intellij] --version "0.3.0"))
        assert equal $both ($base | append [".vscode/settings.json" ".vscode/extensions.json" ".idea/jsonSchemas.xml"] | sort)
    } }
    { name: "an editor given twice is planned once", run: {||
        let plan = (scaffold plan --ci gitlab --editor [vscode vscode] --version "0.3.0")
        assert equal ($plan | where path == ".vscode/settings.json" | length) 1
    } }
    { name: "every image reference and schema address is pinned to the version", run: {||
        for ci in ($PIPELINES | columns) {
            let plan = (scaffold plan --ci $ci --editor [vscode intellij] --version "0.3.0")
            for f in $plan {
                let images = ($f.content | parse --regex 'ghcr\.io/bond-os/nexus-cleanup:(?P<tag>\S*?)[\s\x27"]' | get tag)
                assert ($images | all {|t| $t == "0.3.0" }) $"($ci) ($f.path): ($images)"
                let schemas = ($f.content | parse --regex '(?P<url>https://\S*?/schema/config\.schema\.json)' | get url)
                assert ($schemas | all {|u| $u == $SCHEMA_030 }) $"($ci) ($f.path): ($schemas)"
            }
            let pipeline = (file $plan ($PIPELINES | get $ci))
            if $ci == "forgejo" {
                # Forgejo fetches the tool at its release tag instead of running the image.
                assert ($pipeline | str contains "NEXUS_CLEANUP_VERSION: v0.3.0") $ci
            } else {
                assert ($pipeline | str contains "ghcr.io/bond-os/nexus-cleanup:0.3.0") $ci
            }
            for p in ["configs/example.yaml" ".vscode/settings.json" ".idea/jsonSchemas.xml"] {
                assert (file $plan $p | str contains $SCHEMA_030) $"($ci) ($p)"
            }
        }
    } }
    { name: "no placeholder survives rendering", run: {||
        for ci in ($PIPELINES | columns) {
            for f in (scaffold plan --ci $ci --editor [vscode intellij] --version "0.3.0") {
                # Forgejo's own `${{ … }}` expressions are the pipeline's, not ours.
                let ours = ($f.content | str replace --all '${{ ' '')
                assert not ($ours | str contains "{{") $"($ci) ($f.path)"
            }
        }
    } }
    { name: "the example configuration starts with the pinned modeline", run: {||
        let example = (file (scaffold plan --ci gitlab --version "0.3.0") "configs/example.yaml")
        assert equal ($example | lines | first) $"# yaml-language-server: $schema=($SCHEMA_030)"
    } }
    { name: ".editorconfig and .gitattributes hold exactly the specified lines", run: {||
        let plan = (scaffold plan --ci gitlab --version "0.3.0")
        assert equal (file $plan ".editorconfig") "root = true\n\n[*]\ncharset = utf-8\nend_of_line = lf\n"
        assert equal (file $plan ".gitattributes") "* text=auto eol=lf\n"
    } }
    { name: "init writes no release marker", run: {||
        for ci in ($PIPELINES | columns) {
            for f in (scaffold plan --ci $ci --editor [vscode intellij] --version "0.3.0") {
                assert not ($f.content | str contains "x-release-please") $"($ci) ($f.path)"
            }
        }
    } }
    { name: "an unknown CI system is a usage error naming it and listing the choices", run: {||
        assert-usage (raised { scaffold plan --ci github --version "0.3.0" }) "github" "gitlab" "forgejo" "jenkins-docker" "jenkins-sh"
    } }
    { name: "a missing CI system is a usage error listing the choices", run: {||
        assert-usage (raised { scaffold plan --version "0.3.0" }) "--ci" "gitlab" "forgejo" "jenkins-docker" "jenkins-sh"
    } }
    { name: "an unknown editor is a usage error naming it and listing the choices", run: {||
        assert-usage (raised { scaffold plan --ci gitlab --editor [emacs] --version "0.3.0" }) "emacs" "vscode" "intellij"
    } }
    { name: "planning touches no file", run: {||
        let dir = (mktemp -d -t "scaffold-plan-XXXXXX")
        do { cd $dir; scaffold plan --ci gitlab --editor [vscode intellij] --version "0.3.0" | ignore }
        let left = (ls -a $dir | length)
        rm -rf $dir
        assert equal $left 0
    } }
]

# The rendered example, saved where `config load` can read it. Returns its path.
def example-file []: nothing -> string {
    let path = (mktemp -t "example-XXXXXX.yaml")
    file (scaffold plan --ci gitlab --version "0.3.0") "configs/example.yaml" | save --force --raw $path
    $path
}

run-suite "scaffold example configuration" [
    { name: "the rendered example is accepted by config load and by --require-cap", run: {||
        let path = (example-file)
        let loaded = (config load $path)
        let resolved = (with-env {NEXUS_URL: "https://nexus.test"} {
            config resolve {require_cap: true} --file $loaded
        })
        rm -f $path
        assert equal $resolved.repositories ["replace-me"]
        assert equal $resolved.disabled false
    } }
    { name: "the example shows how to disable it, commented out", run: {||
        let content = (file (scaffold plan --ci gitlab --version "0.3.0") "configs/example.yaml")
        assert ($content | lines | any {|l| $l == "# disabled: true" })
        assert ($content | str contains "every run skips it")
    } }
    { name: "an unedited example fails naming replace-me before any component request", run: {||
        let path = (example-file)
        let log = (mktemp -t "requests-XXXXXX")
        let fetch = {|req|
            $"($req.method) ($req.url)\n" | save --append --raw $log
            if ($req.url | str ends-with "/service/rest/v1/repositories") {
                {status: 200, body: [{name: "yum-proxy", format: "yum", type: "proxy"}]}
            } else {
                {status: 200, body: {items: [], continuationToken: null}}
            }
        }
        let config = (with-env {NEXUS_URL: "https://n.test"} {
            config resolve {require_cap: true} --file (config load $path)
        })
        let err = (raised { cleanup run $config (api client "https://n.test" --backoff 0ms --fetch $fetch) })
        let requests = (open --raw $log | lines)
        rm -f $path $log
        assert not equal $err null "the run succeeded"
        assert ($err.msg | str contains "'replace-me' does not exist") $err.msg
        assert equal $requests ["GET https://n.test/service/rest/v1/repositories"]
    } }
]

# Plan for GitLab at 0.3.0 and write it into `dir` in a child process, so that its
# stdout and stderr can be told apart. An error is printed as its bare message, as the
# entrypoint does: Nushell's own rendering wraps long lines when there is no terminal.
def write-into [dir: string, --force]: nothing -> record {
    let module = ($env.FILE_PWD | path dirname | path join "nexus-cleanup" "scaffold.nu")
    let force_flag = (if $force { "--force" } else { "" })
    let script = $"use '($module)' *
        try { scaffold write \(scaffold plan --ci gitlab --version 0.3.0\) '($dir)' ($force_flag) } catch {|e| print --stderr $e.msg; exit 2 }"
    ^$nu.current-exe -c $script | complete
}

def gitlab-paths []: nothing -> list<string> { paths (scaffold plan --ci gitlab --version "0.3.0") }

def files-under [dir: string]: nothing -> list<string> {
    glob $"($dir)/**/*" --no-dir | path relative-to $dir | sort
}

run-suite "scaffold write" [
    { name: "an empty directory receives every planned file, listed on stderr", run: {||
        let dir = (mktemp -d -t "scaffold-write-XXXXXX")
        let r = (write-into $dir)
        let written = (files-under $dir)
        let plan = (scaffold plan --ci gitlab --version "0.3.0")
        let contents_match = ($plan | all {|f| (open --raw ($dir | path join $f.path) | decode utf-8) == $f.content })
        rm -rf $dir
        assert equal $r.exit_code 0 $r.stderr
        assert equal $written (gitlab-paths)
        assert $contents_match "a written file differs from its plan"
        assert equal $r.stdout ""
        for p in (gitlab-paths) { assert ($r.stderr | str contains $p) $p }
    } }
    { name: "a missing directory is created, parents included", run: {||
        let base = (mktemp -d -t "scaffold-write-XXXXXX")
        let dir = ($base | path join "a" "cleanup-repo")
        let r = (write-into $dir)
        let written = (files-under $dir)
        rm -rf $base
        assert equal $r.exit_code 0 $r.stderr
        assert equal $written (gitlab-paths)
    } }
    { name: "existing files are listed, all of them, and nothing is written", run: {||
        let dir = (mktemp -d -t "scaffold-write-XXXXXX")
        "mine\n" | save ($dir | path join ".gitlab-ci.yml")
        "mine\n" | save ($dir | path join ".editorconfig")
        let r = (write-into $dir)
        let written = (files-under $dir)
        let kept = (open --raw ($dir | path join ".gitlab-ci.yml") | decode utf-8)
        rm -rf $dir
        assert not equal $r.exit_code 0
        assert ($r.stderr | str contains "usage:") $r.stderr
        assert ($r.stderr | str contains ".gitlab-ci.yml") $r.stderr
        assert ($r.stderr | str contains ".editorconfig") $r.stderr
        assert ($r.stderr | str contains "--force") $r.stderr
        assert equal $written [".editorconfig" ".gitlab-ci.yml"]
        assert equal $kept "mine\n"
    } }
    { name: "a dangling symlink counts as an existing file", run: {||
        let dir = (mktemp -d -t "scaffold-write-XXXXXX")
        ^ln -s nowhere ($dir | path join ".gitattributes")
        let r = (write-into $dir)
        let written = (files-under $dir)
        rm -rf $dir
        assert not equal $r.exit_code 0
        assert ($r.stderr | str contains ".gitattributes") $r.stderr
        assert equal $written [".gitattributes"]
    } }
    { name: "--force overwrites what init writes and touches nothing else", run: {||
        let dir = (mktemp -d -t "scaffold-write-XXXXXX")
        mkdir ($dir | path join "configs")
        "mine\n" | save ($dir | path join ".gitlab-ci.yml")
        "mine\n" | save ($dir | path join ".editorconfig")
        "repositories: [prod]\n" | save ($dir | path join "configs" "prod.yaml")
        let r = (write-into $dir --force)
        let written = (files-under $dir)
        let plan = (scaffold plan --ci gitlab --version "0.3.0")
        let pipeline = (open --raw ($dir | path join ".gitlab-ci.yml") | decode utf-8)
        let prod = (open --raw ($dir | path join "configs" "prod.yaml") | decode utf-8)
        rm -rf $dir
        assert equal $r.exit_code 0 $r.stderr
        assert equal $written ((gitlab-paths) | append "configs/prod.yaml" | sort)
        assert equal $pipeline (file $plan ".gitlab-ci.yml")
        assert equal $prod "repositories: [prod]\n"
        assert not ($r.stderr | str contains "prod.yaml")
    } }
    { name: "a write that fails part-way stops and names what was already written", run: {||
        let dir = (mktemp -d -t "scaffold-write-XXXXXX")
        # A file where a directory must go: ci/run-configs.sh cannot be created.
        "x" | save ($dir | path join "ci")
        let r = (write-into $dir)
        rm -rf $dir
        assert not equal $r.exit_code 0
        assert ($r.stderr | str contains "ci/run-configs.sh") $r.stderr
        assert ($r.stderr | str contains "already written") $r.stderr
        assert ($r.stderr | str contains ".gitlab-ci.yml") $r.stderr
    } }
]

# Every element below an XML record, depth first.
def xml-elements [node: record]: nothing -> list<record> {
    if ($node.tag? | default null) == null { return [] }
    [$node] | append ($node.content | each {|c| xml-elements $c } | flatten)
}

def editor-plan [...markers: string]: nothing -> list {
    if ($markers | is-empty) {
        scaffold plan --ci gitlab --editor [vscode intellij] --version "0.3.0"
    } else {
        scaffold plan --ci gitlab --editor [vscode intellij] --version "0.3.0" --release-markers
    }
}

run-suite "scaffold editor files" [
    { name: "the IntelliJ mapping parses as XML and maps the pinned URL to both patterns", run: {||
        for plan in [(editor-plan) (editor-plan "markers")] {
            let xml = (file $plan ".idea/jsonSchemas.xml" | from xml)
            assert equal $xml.tag "project"
            let elements = (xml-elements $xml)
            assert equal ($elements | where tag == "component" | get attributes.name) ["JsonSchemaMappingsProjectConfiguration"]
            let options = ($elements | where tag == "option" | get attributes)
            let schema = ($options | where name == "relativePathToSchema" | get value)
            assert equal $schema [$SCHEMA_030]
            let patterns = ($options | where name == "path" | get value)
            assert equal $patterns ["configs/*.yaml" "configs/*.yml"]
            assert ($options | where name == "mappingKind" | all {|o| $o.value == "Pattern" })
        }
    } }
    { name: "the VS Code settings parse as JSON with comments and map the pinned URL to both patterns", run: {||
        for plan in [(editor-plan) (editor-plan "markers")] {
            let settings = (file $plan ".vscode/settings.json" | from json)
            assert equal ($settings | get "yaml.schemas" | columns) [$SCHEMA_030]
            assert equal ($settings | get "yaml.schemas" | get $SCHEMA_030) ["configs/*.yaml" "configs/*.yml"]
        }
    } }
    { name: "the IntelliJ mapping ends without a final newline, as the IDE writes it", run: {||
        # Captured from IntelliJ IDEA: a trailing newline would show as a diff the first
        # time the IDE saves the file again.
        for plan in [(editor-plan) (editor-plan "markers")] {
            assert (file $plan ".idea/jsonSchemas.xml" | str ends-with "</project>")
        }
    } }
    { name: "the VS Code recommendations name Red Hat's YAML extension", run: {||
        let ext = (file (editor-plan) ".vscode/extensions.json" | from json)
        assert equal $ext.recommendations ["redhat.vscode-yaml"]
    } }
]

# The Nexus URL a planned pipeline sets for itself, or null when it sets none.
def pipeline-url [ci: string]: nothing -> any {
    let content = (file (scaffold plan --ci $ci --version "0.3.0") ($PIPELINES | get $ci))
    $content | parse --regex `NEXUS_URL(?::|\s*=)\s*'?(?P<url>https?://[^'\s]+)` | get --optional 0.url
}

run-suite "scaffold pipeline URL" [
    { name: "a pipeline that sets the URL itself sets a placeholder the tool refuses", run: {||
        for ci in ["gitlab" "jenkins-docker" "jenkins-sh"] {
            let url = (pipeline-url $ci)
            assert not equal $url null $"($ci) sets no NEXUS_URL"
            let err = (raised {
                with-env {NEXUS_URL: $url, NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} { config resolve {repositories: ["r"]} }
            })
            assert-usage $err "NEXUS_URL" $url "a placeholder"
        }
    } }
    { name: "the Forgejo pipeline reads the URL from a variable with no default", run: {||
        assert equal (pipeline-url "forgejo") null
        let content = (file (scaffold plan --ci forgejo --version "0.3.0") ($PIPELINES | get forgejo))
        assert ($content | str contains 'NEXUS_URL: ${{ vars.NEXUS_URL }}')
    } }
]
