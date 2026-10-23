use ./harness.nu *
use ../nexus-cleanup/scaffold.nu *
use ../nexus-cleanup/version.nu [VERSION]

# Exercises ci/run-configs.sh, the loop every generated pipeline calls, as `init`
# writes it, with a stub in place of the tool. The script is POSIX sh by design, so
# this suite runs it with `sh` — BusyBox's in the pinned image.

# The stub logs its arguments, writes the summary where asked as the tool does,
# prints a report in the config file's `format` (JSON when absent; a CSV report opens
# with its header, as the tool's does), and exits with the code named in the file's
# `# stub-exit: N` line (0 when absent).
const STUB = '
echo "$*" >> "$STUB_LOG"
prev=""
for a in "$@"; do
    case "$a" in *.yaml) f="$a" ;; esac
    if [ "$prev" = "--summary-out" ]; then echo "{}" > "$a"; fi
    prev="$a"
done
if grep -q "^format: csv" "$f"; then echo "repository,format"; else echo "{}"; fi
code=$(sed -n "s/^# stub-exit: //p" "$f")
exit "${code:-0}"
'

# Run the script in a repository written by `init`, its example configuration
# replaced by one file per exit code. CONFIG_DIR and REPORT_DIR are left unset, so
# the script's own defaults are what is tested.
def run-loop [codes: list<int>, ...args: string, --csv: list<int> = []]: nothing -> record {
    let work = (mktemp -d -t "run-configs-XXXXXX")
    scaffold write (scaffold plan --ci gitlab --version $VERSION) $work --quiet
    rm $"($work)/configs/example.yaml"
    for i in 0..<($codes | length) {
        let format = (if $i in $csv { "format: csv\n" } else { "" })
        $"# stub-exit: ($codes | get $i)\nrepositories: [r]\n($format)" | save $"($work)/configs/c($i).yaml"
    }
    $STUB | save $"($work)/stub.sh"
    let log = $"($work)/log"
    "" | save $log
    let r = (with-env {NEXUS_CLEANUP: $"sh ($work)/stub.sh", STUB_LOG: $log} {
        cd $work
        ^sh ci/run-configs.sh ...$args | complete
    })
    let calls = (open --raw $log | lines | where {|l| $l | is-not-empty })
    let reports = (if ($"($work)/reports" | path exists) { ls $"($work)/reports" | get name | each {|p| $p | path basename } | sort } else { [] })
    rm -rf $work
    {exit_code: $r.exit_code, stderr: $r.stderr, calls: $calls, reports: $reports}
}

run-suite "run-configs.sh" [
    { name: "skipped groups in one file end the job with 4", run: {||
        let r = (run-loop [0 4 0])
        assert equal $r.exit_code 4
        assert equal ($r.calls | length) 3
    } }
    { name: "a failing file does not stop the others, and its code wins over 4", run: {||
        let r = (run-loop [0 3 4])
        assert equal $r.exit_code 3
        assert equal ($r.calls | length) 3
        assert ($r.stderr | str contains "c1.yaml: exited 3")
    } }
    { name: "the first failing code is the job's", run: {||
        assert equal (run-loop [5 1 0] | get exit_code) 5
    } }
    { name: "all files clean ends the job with 0", run: {||
        assert equal (run-loop [0 0] | get exit_code) 0
    } }
    { name: "an empty directory fails rather than passing having run nothing", run: {||
        let r = (run-loop [])
        assert not equal $r.exit_code 0
        assert ($r.stderr | str contains "no configuration file")
        assert equal $r.calls []
    } }
    { name: "files run in sorted order, each with --require-cap and a report of its own", run: {||
        let r = (run-loop [0 0 0])
        assert equal ($r.calls | each {|c| $c | parse --regex '--config (?P<f>\S+)' | get f.0 }) ["configs/c0.yaml" "configs/c1.yaml" "configs/c2.yaml"]
        assert ($r.calls | all {|c| $c | str contains "--require-cap" })
        assert equal $r.reports ["c0.dry-run.json" "c0.dry-run.summary.json" "c1.dry-run.json" "c1.dry-run.summary.json" "c2.dry-run.json" "c2.dry-run.summary.json"]
    } }
    { name: "--execute reaches the tool only when given", run: {||
        assert not ((run-loop [0]).calls | any {|c| $c | str contains "--execute" })
        let r = (run-loop [0] "--execute")
        assert ($r.calls | all {|c| $c | str contains "--execute" })
        assert equal $r.reports ["c0.execute.json" "c0.execute.summary.json"]
    } }
    { name: "each report is named after the format its file asked for", run: {||
        let r = (run-loop [0 0] --csv [1])
        assert equal $r.reports ["c0.dry-run.json" "c0.dry-run.summary.json" "c1.dry-run.csv" "c1.dry-run.summary.json"]
        let r = (run-loop [0] "--execute" --csv [0])
        assert equal $r.reports ["c0.execute.csv" "c0.execute.summary.json"]
    } }
    { name: "any other argument is refused before anything runs", run: {||
        let r = (run-loop [0] "--keep" "1")
        assert equal $r.exit_code 2
        assert equal $r.calls []
    } }
]

# A system's rendered pipeline, as `init` writes it.
def pipeline [ci: string]: nothing -> string {
    scaffold plan --ci $ci --version $VERSION | where path == ($CI_SYSTEMS | get $ci) | get content.0
}

run-suite "generated pipelines" [
    { name: "GitLab: parses; only the manual execute job passes --execute; a schedule runs the dry run only", run: {||
        let p = (pipeline gitlab | from yaml)
        let dry = ($p | get "nexus-cleanup:dry-run")
        let exec = ($p | get "nexus-cleanup:execute")
        assert not ($dry.script | any {|l| $l | str contains "--execute" })
        assert ($dry.script | any {|l| $l == "sh ci/run-configs.sh" })
        assert ($dry.rules | any {|r| $r.if | str contains '"schedule"' })
        assert equal $exec.script ["sh ci/run-configs.sh --execute"]
        assert ($exec.rules | all {|r| ($r.when? | default "") == "manual" })
        assert not ($exec.rules | any {|r| $r.if | str contains "schedule" })
        assert ($exec.rules | all {|r| $r.if | str contains '$CI_PIPELINE_SOURCE == "web"' })
        let others = ($p | transpose job body | where job not-in ["nexus-cleanup:dry-run" "nexus-cleanup:execute"])
        assert not ($others | any {|j| $j.body | to yaml | str contains "--execute" })
    } }
    { name: "Forgejo: parses; only the dispatched execute step passes --execute", run: {||
        let p = (pipeline forgejo | from yaml)
        # YAML 1.1 reads the `on` key as true in some parsers; accept either.
        let triggers = ($p | get --optional on | default ($p | get --optional true))
        assert ("schedule" in ($triggers | columns))
        assert equal ($triggers.workflow_dispatch.inputs.execute.default) false
        let steps = ($p.jobs.cleanup.steps | where {|s| ($s.run? | default "") | str contains "run-configs.sh" })
        assert equal ($steps | length) 2
        let dry = ($steps | where name == "Dry run" | first)
        assert not ($dry.run | str contains "--execute")
        assert ($dry.if? == null) "the dry run must run on every trigger"
        let exec = ($steps | where name == "Execute" | first)
        assert ($exec.run | str contains "sh ci/run-configs.sh --execute")
        assert ($exec.if | str contains "github.event_name == 'workflow_dispatch'")
        assert ($exec.if | str contains "inputs.execute")
    } }
    { name: "Jenkins: --execute only in the Execute stage, behind an input step, never on the timer", run: {||
        for ci in ["jenkins-docker" "jenkins-sh"] {
            let text = (pipeline $ci)
            let parts = ($text | split row "stage('Execute')")
            assert equal ($parts | length) 2 $ci
            assert not ($parts.0 | str contains "--execute") $ci
            assert ($parts.0 | str contains "ci/run-configs.sh") $ci
            let exec = $parts.1
            assert (($exec | str index-of "input {") < ($exec | str index-of "ci/run-configs.sh --execute")) $ci
            assert ($exec | str contains "not { triggeredBy 'TimerTrigger' }") $ci
            assert ($exec | str contains "expression { params.EXECUTE }") $ci
            assert ($text | str contains "booleanParam(name: 'EXECUTE', defaultValue: false") $ci
        }
    } }
    { name: "every pipeline calls the loop init writes beside it, and reads configs/", run: {||
        for ci in ($CI_SYSTEMS | columns) {
            let plan = (scaffold plan --ci $ci --version $VERSION)
            assert ("ci/run-configs.sh" in ($plan | get path)) $ci
            let text = (pipeline $ci)
            # jenkins-sh runs it as `docker run --entrypoint sh IMAGE ci/run-configs.sh`.
            assert ($text =~ "\\bsh\\b[^\\n]* ci/run-configs\\.sh") $ci
            assert not ($text | str contains "examples/") $ci
            assert not ($text | str contains "CONFIG_DIR") $ci
        }
    } }
]
