use ./harness.nu *
use ../nexus-cleanup/config.nu *
use ../nexus-cleanup/run.nu *
use ../nexus-cleanup/api.nu *
use ../nexus-cleanup/report.nu [FIELDS]
use ../nexus-cleanup/version.nu [VERSION]

def entrypoint []: nothing -> string { $"($env.FILE_PWD | path dirname)/nexus-cleanup.nu" }

# Run the entrypoint with a clean environment so the developer's own NEXUS_* variables
# cannot make a usage test pass by accident.
def cli [...args: string]: nothing -> record {
    with-env {NEXUS_URL: "", NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
        ^$nu.current-exe (entrypoint) ...$args | complete
    }
}

def fixture [name: string]: nothing -> string { $"($env.FILE_PWD)/fixtures/config/($name)" }

run-suite "cli: configuration file" [
    { name: "an invalid file exits with the usage code, naming it, before any request", run: {||
        # The URL is unreachable: reaching it would exit with the API code instead.
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "misspelt-key.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "misspelt-key.yaml")
        assert ($r.stderr | str contains "keeep")
    } }
    { name: "a missing file exits with the usage code", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "absent.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "absent.yaml")
    } }
    { name: "a flag overrides the file's value", run: {||
        # The file's keep: 0 alone is a usage error; --keep 5 replaces it, so the run
        # gets as far as the unreachable Nexus.
        let alone = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "keep-zero.yaml"))
        assert equal $alone.exit_code $EXIT_USAGE
        assert ($alone.stderr | str contains "'keep' in")
        let r = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec"
            "--config" (fixture "keep-zero.yaml") "--keep" "5")
        assert equal $r.exit_code $EXIT_API
    } }
    { name: "execute in the file is refused, pointing at the flag", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "execute-true.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--execute")
    } }
    { name: "--require-cap without a cap exits with the usage code before any request", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--require-cap" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--max-deletions")
        let capped = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec"
            "--require-cap" "--config" (fixture "capped.yaml"))
        assert equal $capped.exit_code $EXIT_API
    } }
    { name: "--version ignores a broken configuration file", run: {||
        let r = (cli "--version" "--config" (fixture "invalid.yaml"))
        assert equal $r.exit_code 0
        assert equal ($r.stdout | str trim) $VERSION
    } }
    { name: "--help still states each flag's default", run: {||
        let help = (cli "--help" | get stdout)
        for line in [
            ["--keep" "default 1"] ["--timeout" "default 30sec"] ["--max-attempts" "default 4"]
            ["--format" "default json"] ["--max-deletions" "default 0"] ["--max-deletion-share" "default 0"]
        ] {
            let flag_line = ($help | lines | where {|l| $l | str contains $"($line.0) <" } | first)
            assert ($flag_line | str contains $line.1) $"($line.0): ($flag_line)"
        }
        assert ($help | str contains "--config")
    } }
]

run-suite "cli" [
    { name: "no repository selection exits with the usage code", run: {||
        let r = (cli)
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "NEXUS_URL")
    } }
    { name: "an invalid keep count exits with the usage code before any request", run: {||
        let r = (cli "--url" "https://nexus.test" "--keep" "0" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "--keep")
    } }
    { name: "an invalid output format exits with the usage code", run: {||
        let r = (cli "--url" "https://nexus.test" "--format" "yaml" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--format")
    } }
    { name: "a scope pattern without a scope group exits with the usage code", run: {||
        let r = (cli "--url" "https://nexus.test" "--scope-from-path" "^/(x)" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--scope-from-path")
    } }
    { name: "an invalid path pattern exits with the usage code before any request", run: {||
        # The URL is unreachable: reaching it would exit with the API code instead.
        let r = (cli "--url" "http://127.0.0.1:9" "--from-path" "^/(?P<name>[^/]+)/" "repo")
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "--from-path")
    } }
    { name: "an unreachable Nexus exits with the API code and writes no report", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec" "repo")
        assert equal $r.exit_code $EXIT_API
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "nexus-cleanup:")
    } }
    { name: "--allow-hosted is accepted and the run goes on to contact Nexus", run: {||
        # The URL is unreachable: an unknown or rejected flag would exit with the usage code.
        let r = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec" "--allow-hosted" "raw-builds")
        assert equal $r.exit_code $EXIT_API
        assert not ($r.stderr | str contains "usage:")
    } }
    { name: "--allow-hosted without --execute is a dry run", run: {||
        let log = (mktemp -t "deletes-XXXXXX")
        let fetch = {|req|
            if $req.method == "DELETE" {
                $"($req.url)\n" | save --append --raw $log
                {status: 204, body: {}}
            } else if ($req.url | str contains "/service/rest/v1/repositories") {
                {status: 200, body: [{name: "raw-builds", format: "raw", type: "hosted"}]}
            } else {
                {status: 200, body: {items: [], continuationToken: null}}
            }
        }
        let config = (config resolve {url: "https://n.test", repositories: ["raw-builds"], allow_hosted: true})
        let out = (cleanup run $config (api client "https://n.test" --backoff 0ms --fetch $fetch))
        assert equal (open --raw $log | str trim) ""
        rm -f $log
        assert equal $out.report.summary.mode "dry-run"
    } }
    { name: "--help describes --allow-hosted", run: {||
        let help = (cli "--help" | get stdout)
        let line = ($help | lines | where {|l| $l | str contains "--allow-hosted" } | first)
        assert ($line | str contains "raw hosted")
        assert ($line | str contains "--execute")
    } }
    { name: "a usage failure names the setting without echoing the password", run: {||
        let r = (with-env {NEXUS_URL: "", NEXUS_PASSWORD: "hunter2"} {
            ^$nu.current-exe (entrypoint) "--url" "https://n.test" "--keep" "0" "repo" | complete
        })
        assert not ($r.stderr | str contains "hunter2")
    } }

    # --- summary-out alongside CSV (the aggregate CSV has no room for) ---
    { name: "CSV output writes the aggregate to the summary path, leaving stdout the table", run: {||
        let summary_path = (mktemp -t "summary-XXXXXX.json")
        let script = (mktemp -t "emit-probe-XXXXXX.nu")
        let root = ($env.FILE_PWD | path dirname)
        [
            $"use ($root)/nexus-cleanup/run.nu *"
            "let report = {"
            "    summary: {mode: 'dry-run', counts: {components_total: 1, kept: 1, to_delete: 0, skipped: 0, failed: 0, deleted: 0, groups_total: 1, groups_skipped: 0}}"
            "    records: [{"
            "        repository: 'r', format: 'npm', scope: '*', group: '', name: 'w', variant: '*'"
            "        version: '1.0.0', component_id: 'w-1', decision: 'keep', reason: 'group-within-keep'"
            "        rank: null, size_bytes: 10, last_modified: '', deleted: false, error: '', path: '/w-1.tgz'"
            "    }]"
            "}"
            $"cleanup emit $report 'csv' '($summary_path)'"
        ] | str join "\n" | save --force $script

        let r = (^$nu.current-exe $script | complete)
        rm -f $script
        assert equal $r.exit_code 0

        # stdout is the CSV table and nothing else
        let lines = ($r.stdout | str trim | lines)
        assert equal ($lines | first) ($FIELDS | str join ",")
        assert equal ($lines | length) 2
        assert not ($r.stdout | str contains "components_total")

        # the aggregate landed in the file, as JSON
        let summary = (open $summary_path)
        assert equal $summary.counts.components_total 1
        rm -f $summary_path
    } }
]

# Run the entrypoint from `dir`, with the same clean environment as `cli`.
def cli-in [dir: string, ...args: string]: nothing -> record {
    let ep = (entrypoint)
    with-env {NEXUS_URL: "", NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
        cd $dir
        ^$nu.current-exe $ep ...$args | complete
    }
}

def tree [dir: string]: nothing -> list<string> {
    glob $"($dir)/**/*" --no-dir | path relative-to $dir | sort
}

# Run `init` with these arguments in a fresh directory; returns the result and the
# files left behind.
def init-in-empty [...args: string]: nothing -> record {
    let dir = (mktemp -d -t "init-XXXXXX")
    let r = (cli-in $dir "init" ...$args)
    let files = (tree $dir)
    rm -rf $dir
    $r | insert files $files
}

const GITLAB_TREE = [".editorconfig" ".gitattributes" ".gitlab-ci.yml" "ci/run-configs.sh" "configs/example.yaml"]

run-suite "cli: init" [
    { name: "init writes the repository with no NEXUS_URL and no selection", run: {||
        let r = (init-in-empty "--ci" "gitlab")
        assert equal $r.exit_code 0 $r.stderr
        assert equal $r.stdout ""
        assert equal $r.files $GITLAB_TREE
        assert ($r.stderr | str contains "configs/example.yaml")
    } }
    { name: "init writes into a named directory, creating it", run: {||
        let base = (mktemp -d -t "init-XXXXXX")
        let r = (cli-in $base "init" "--ci" "gitlab" "cleanup-repo")
        let files = (tree ($base | path join "cleanup-repo"))
        let beside = (ls -a $base | get name | path basename)
        rm -rf $base
        assert equal $r.exit_code 0 $r.stderr
        assert equal $files $GITLAB_TREE
        assert equal $beside ["cleanup-repo"]
    } }
    { name: "the files pin the running tool's version", run: {||
        let dir = (mktemp -d -t "init-XXXXXX")
        let r = (cli-in $dir "init" "--ci" "gitlab")
        let pipeline = (open --raw ($dir | path join ".gitlab-ci.yml") | decode utf-8)
        let example = (open --raw ($dir | path join "configs" "example.yaml") | decode utf-8)
        rm -rf $dir
        assert equal $r.exit_code 0 $r.stderr
        assert ($pipeline | str contains $"ghcr.io/bond-os/nexus-cleanup:($VERSION)")
        assert ($example | str contains $"/v($VERSION)/schema/config.schema.json")
    } }
    { name: "--editor is repeatable, in either spelling", run: {||
        let r = (init-in-empty "--ci=jenkins-sh" "--editor" "vscode" "--editor=intellij")
        assert equal $r.exit_code 0 $r.stderr
        assert ("Jenkinsfile" in $r.files)
        assert (".vscode/settings.json" in $r.files)
        assert (".vscode/extensions.json" in $r.files)
        assert (".idea/jsonSchemas.xml" in $r.files)
    } }
    { name: "init without --ci exits with the usage code, lists the choices, writes nothing", run: {||
        let r = (init-in-empty)
        assert equal $r.exit_code $EXIT_USAGE
        for c in ["gitlab" "forgejo" "jenkins-docker" "jenkins-sh"] { assert ($r.stderr | str contains $c) $c }
        assert equal $r.files []
    } }
    { name: "an unknown CI system exits with the usage code, naming it", run: {||
        let r = (init-in-empty "--ci" "github")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "github")
        for c in ["gitlab" "forgejo" "jenkins-docker" "jenkins-sh"] { assert ($r.stderr | str contains $c) $c }
        assert equal $r.files []
    } }
    { name: "an unknown editor exits with the usage code, listing the editors", run: {||
        let r = (init-in-empty "--ci" "gitlab" "--editor" "emacs")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "emacs")
        assert ($r.stderr | str contains "vscode")
        assert ($r.stderr | str contains "intellij")
        assert equal $r.files []
    } }
    { name: "a run flag given to init exits with the usage code and writes nothing", run: {||
        let r = (init-in-empty "--ci" "gitlab" "--execute")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--execute")
        assert equal $r.files []
    } }
    { name: "a flag missing its value exits with the usage code", run: {||
        let r = (init-in-empty "--ci")
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.files []
    } }
    { name: "two target directories exit with the usage code", run: {||
        let r = (init-in-empty "--ci" "gitlab" "a" "b")
        assert equal $r.exit_code $EXIT_USAGE
        assert equal $r.files []
    } }
    { name: "existing files exit with the usage code; --force overwrites them", run: {||
        let dir = (mktemp -d -t "init-XXXXXX")
        "mine\n" | save ($dir | path join ".gitlab-ci.yml")
        let refused = (cli-in $dir "init" "--ci" "gitlab")
        let after_refusal = (tree $dir)
        let forced = (cli-in $dir "init" "--ci" "gitlab" "--force")
        let after_force = (tree $dir)
        rm -rf $dir
        assert equal $refused.exit_code $EXIT_USAGE
        assert ($refused.stderr | str contains ".gitlab-ci.yml")
        assert equal $after_refusal [".gitlab-ci.yml"]
        assert equal $forced.exit_code 0 $forced.stderr
        assert equal $after_force $GITLAB_TREE
    } }
    { name: "init --help describes its options and writes nothing", run: {||
        let r = (init-in-empty "--help")
        assert equal $r.exit_code 0
        for word in ["--ci" "--editor" "--force" "gitlab" "jenkins-sh" "vscode" "intellij"] {
            assert ($r.stdout | str contains $word) $word
        }
        assert equal $r.files []
    } }
    { name: "a repository named init is still selected by --pattern", run: {||
        # Through the entrypoint, `--pattern init` is a cleanup run: it reaches the
        # (unreachable) Nexus instead of initialising anything.
        let dir = (mktemp -d -t "init-XXXXXX")
        let run = (cli-in $dir "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec" "--pattern" "init")
        let files = (tree $dir)
        rm -rf $dir
        assert equal $run.exit_code $EXIT_API $run.stderr
        assert equal $files []
        # And the selection it makes picks the repository named init.
        let fetch = {|req|
            if ($req.url | str ends-with "/service/rest/v1/repositories") {
                {status: 200, body: [{name: "init", format: "npm", type: "proxy"}]}
            } else {
                {status: 200, body: {items: [], continuationToken: null}}
            }
        }
        let config = (config resolve {url: "https://n.test", pattern: "init"})
        let out = (cleanup run $config (api client "https://n.test" --backoff 0ms --fetch $fetch))
        assert equal $out.report.summary.repositories ["init"]
    } }
]

# Run the entrypoint from a fresh directory with NEXUS_URL set to `url`; returns the
# result and the files left behind.
def cli-with-url [url: string, ...args: string]: nothing -> record {
    let dir = (mktemp -d -t "url-XXXXXX")
    let ep = (entrypoint)
    let r = (with-env {NEXUS_URL: $url, NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
        cd $dir
        ^$nu.current-exe $ep ...$args | complete
    })
    let files = (tree $dir)
    rm -rf $dir
    $r | insert files $files
}

# Resolve and run in-process with NEXUS_URL set to `url` and a fetch stub that fails
# the test on any request; returns the error message.
def refused-in-process [url: string, flags: record]: nothing -> string {
    let fetch = {|req| error make {msg: $"unexpected request: ($req.method) ($req.url)"} }
    let err = (try {
        let config = (with-env {NEXUS_URL: $url, NEXUS_USERNAME: "", NEXUS_PASSWORD: ""} {
            config resolve ({repositories: ["repo"]} | merge $flags)
        })
        cleanup run $config (api client $url --max-attempts 1 --backoff 0ms --fetch $fetch)
        null
    } catch {|e| $e })
    assert not equal $err null "the run succeeded"
    assert not ($err.msg | str contains "unexpected request") $err.msg
    $err.msg
}

run-suite "cli: Nexus URL" [
    { name: "a placeholder NEXUS_URL exits with the usage code before an invalid keep count", run: {||
        let r = (cli-with-url "https://nexus.example.com" "--keep" "0" "repo")
        assert equal $r.exit_code $EXIT_USAGE $r.stderr
        assert equal $r.stdout ""
        assert ($r.stderr | str contains "NEXUS_URL is 'https://nexus.example.com', a placeholder")
        assert ((refused-in-process "https://nexus.example.com" {keep: 0}) | str contains "a placeholder")
    } }
    { name: "an unparseable NEXUS_URL exits with the usage code, quoting it", run: {||
        let r = (cli-with-url "http//nexus" "repo")
        assert equal $r.exit_code $EXIT_USAGE $r.stderr
        assert ($r.stderr | str contains "NEXUS_URL must be an http or https URL, got 'http//nexus'")
        assert ((refused-in-process "http//nexus" {}) | str contains "must be an http or https URL")
    } }
    { name: "--version ignores a placeholder NEXUS_URL", run: {||
        let r = (cli-with-url "https://nexus.example.com" "--version")
        assert equal $r.exit_code 0 $r.stderr
        assert equal ($r.stdout | str trim) $VERSION
    } }
    { name: "init ignores a placeholder NEXUS_URL", run: {||
        let r = (cli-with-url "https://nexus.example.com" "init" "--ci" "gitlab")
        assert equal $r.exit_code 0 $r.stderr
        assert equal $r.files $GITLAB_TREE
    } }
]

# The URL is unreachable throughout: a run that sent a request would exit with the
# API code, so exit 0 or 2 shows that none was sent.
run-suite "cli: disabled file" [
    { name: "JSON output is a valid report of nothing, marked disabled", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled.yaml"))
        assert equal $r.exit_code 0 $r.stderr
        let doc = ($r.stdout | from json)
        assert equal $doc.records []
        assert equal $doc.summary.disabled true
        assert equal ($doc.summary.counts | values | math sum) 0
        assert ($r.stderr | str contains "disabled.yaml is disabled; nothing was done")
    } }
    { name: "CSV output is the header row alone", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled-csv.yaml"))
        assert equal $r.exit_code 0 $r.stderr
        assert equal ($r.stdout | str trim | lines) [($FIELDS | str join ",")]
    } }
    { name: "--summary-out writes the aggregate, marked disabled", run: {||
        let out = (mktemp -t "summary-XXXXXX.json")
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled.yaml") "--summary-out" $out)
        let s = (open $out)
        rm -f $out
        assert equal $r.exit_code 0 $r.stderr
        assert equal $s.disabled true
        assert equal $s.repositories []
    } }
    { name: "--execute exits 0 having deleted nothing", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled.yaml") "--execute")
        assert equal $r.exit_code 0 $r.stderr
        assert equal ($r.stdout | from json | get summary.counts.deleted) 0
    } }
    { name: "a misspelt key in a disabled file is still a usage error", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled-misspelt.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "keeep")
    } }
    { name: "a refused key in a disabled file is still a usage error", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled-execute.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--execute")
    } }
    { name: "--require-cap still requires a cap of a disabled file", run: {||
        let r = (cli "--url" "http://127.0.0.1:9" "--require-cap" "--config" (fixture "disabled-uncapped.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--require-cap")
    } }
    { name: "a disabled file still needs a Nexus URL", run: {||
        let r = (cli "--config" (fixture "disabled.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "NEXUS_URL is not set")
    } }
    { name: "a disabled file still refuses a placeholder NEXUS_URL", run: {||
        let r = (cli-with-url "https://nexus.example.com" "--config" (fixture "disabled.yaml"))
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "NEXUS_URL is 'https://nexus.example.com', a placeholder")
    } }
    { name: "a disabled run needs no password", run: {||
        # `cli` clears NEXUS_PASSWORD.
        let r = (cli "--url" "http://127.0.0.1:9" "--config" (fixture "disabled.yaml"))
        assert equal $r.exit_code 0 $r.stderr
    } }
    { name: "disabled: false runs as if the key were absent", run: {||
        let off = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec" "--config" (fixture "disabled-false.yaml"))
        let absent = (cli "--url" "http://127.0.0.1:9" "--max-attempts" "1" "--timeout" "2sec" "--config" (fixture "capped.yaml"))
        assert equal $off.exit_code $EXIT_API
        assert equal $absent.exit_code $EXIT_API
        assert not ($off.stderr | str contains "is disabled")
    } }
]

run-suite "cli: init --env" [
    { name: "without --env, init writes neither varlock file", run: {||
        let r = (init-in-empty "--ci" "gitlab")
        assert not (".env.schema" in $r.files)
        assert not (".gitignore" in $r.files)
    } }
    { name: "--env varlock writes both files beside the others and lists them", run: {||
        let r = (init-in-empty "--ci" "gitlab" "--env" "varlock")
        assert equal $r.exit_code 0 $r.stderr
        assert equal $r.files ($GITLAB_TREE | append [".env.schema" ".gitignore"] | sort)
        assert ($r.stderr | str contains "wrote .env.schema")
        assert ($r.stderr | str contains "wrote .gitignore")
    } }
    { name: "a repeated --env varlock writes each file once", run: {||
        let r = (init-in-empty "--ci" "gitlab" "--env=varlock" "--env" "varlock")
        assert equal $r.exit_code 0 $r.stderr
        assert equal ($r.stderr | lines | where {|l| $l == "wrote .gitignore" } | length) 1
    } }
    { name: "an unknown environment tool exits with the usage code, lists varlock, writes nothing", run: {||
        let r = (init-in-empty "--ci" "gitlab" "--env" "dotenv")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "dotenv")
        assert ($r.stderr | str contains "varlock")
        assert equal $r.files []
    } }
    { name: "--env without a value exits with the usage code", run: {||
        let r = (init-in-empty "--ci" "gitlab" "--env")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--env needs a value")
    } }
    { name: "init --help lists --env and its choice", run: {||
        let r = (init-in-empty "--help")
        assert ($r.stdout | lines | any {|l| ($l | str contains "--env <tool>") and ($l | str contains "varlock") })
    } }
    { name: "an existing .gitignore is refused, and --force overwrites only what init writes", run: {||
        let dir = (mktemp -d -t "init-XXXXXX")
        "reports/\n" | save ($dir | path join ".gitignore")
        "mine\n" | save ($dir | path join "notes.txt")
        let refused = (cli-in $dir "init" "--ci" "gitlab" "--env" "varlock")
        let after_refusal = (tree $dir)
        let forced = (cli-in $dir "init" "--ci" "gitlab" "--env" "varlock" "--force")
        let ignore = (open --raw ($dir | path join ".gitignore"))
        let notes = (open --raw ($dir | path join "notes.txt"))
        rm -rf $dir
        assert equal $refused.exit_code $EXIT_USAGE
        assert ($refused.stderr | str contains ".gitignore")
        assert equal $after_refusal [".gitignore" "notes.txt"]
        assert equal $forced.exit_code 0 $forced.stderr
        assert equal $ignore ".env\n.env.local\n.env.*.local\n"
        assert equal $notes "mine\n"
    } }
]

run-suite "cli: upgrade" [
    { name: "upgrade moves an init-written repository's pins to this release, listing the files", run: {||
        let dir = (mktemp -d -t "upgrade-XXXXXX")
        cli-in $dir "init" "--ci" "gitlab" "--editor" "vscode" | ignore
        for f in [".gitlab-ci.yml" "configs/example.yaml" ".vscode/settings.json"] {
            let p = ($dir | path join $f)
            open --raw $p | decode utf-8 | str replace --all $VERSION "0.0.1" | save --force --raw $p
        }
        let r = (cli-in $dir "upgrade")
        let pipeline = (open --raw ($dir | path join ".gitlab-ci.yml") | decode utf-8)
        rm -rf $dir
        assert equal $r.exit_code 0 $r.stderr
        assert equal $r.stdout ""
        for f in [".gitlab-ci.yml" "configs/example.yaml" ".vscode/settings.json"] {
            assert ($r.stderr | str contains $"updated ($f)") $f
        }
        assert ($pipeline | str contains $"nexus-cleanup:($VERSION)")
        assert not ($pipeline | str contains "0.0.1")
    } }
    { name: "upgrade takes a directory argument", run: {||
        let base = (mktemp -d -t "upgrade-XXXXXX")
        cli-in $base "init" "--ci" "jenkins-sh" "repo" | ignore
        let r = (cli-in $base "upgrade" "repo")
        rm -rf $base
        assert equal $r.exit_code 0 $r.stderr
        assert ($r.stderr | str contains "nothing to update")
    } }
    { name: "a run flag given to upgrade exits with the usage code and writes nothing", run: {||
        let dir = (mktemp -d -t "upgrade-XXXXXX")
        cli-in $dir "init" "--ci" "gitlab" | ignore
        let p = ($dir | path join ".gitlab-ci.yml")
        open --raw $p | decode utf-8 | str replace --all $VERSION "0.0.1" | save --force --raw $p
        let r = (cli-in $dir "upgrade" "--execute")
        let kept = (open --raw $p | decode utf-8 | str contains "0.0.1")
        rm -rf $dir
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "--execute")
        assert $kept "upgrade --execute changed a file"
    } }
    { name: "a missing directory exits with the usage code", run: {||
        let r = (cli "upgrade" "/nonexistent/nexus-cleanup-upgrade")
        assert equal $r.exit_code $EXIT_USAGE
        assert ($r.stderr | str contains "not a directory")
    } }
    { name: "upgrade --help names the version it upgrades to", run: {||
        let r = (cli "upgrade" "--help")
        assert equal $r.exit_code 0
        assert ($r.stdout | str contains "nexus-cleanup upgrade [DIR]")
        assert ($r.stdout | str contains $VERSION)
    } }
    { name: "upgrade ignores a placeholder or missing NEXUS_URL", run: {||
        let dir = (mktemp -d -t "upgrade-XXXXXX")
        cli-in $dir "init" "--ci" "gitlab" | ignore
        let placeholder = (cli-with-url "https://nexus.example.com" "upgrade" $dir)
        let unset = (cli "upgrade" $dir)
        rm -rf $dir
        assert equal $placeholder.exit_code 0 $placeholder.stderr
        assert equal $unset.exit_code 0 $unset.stderr
    } }
]
