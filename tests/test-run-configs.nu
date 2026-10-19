use ./harness.nu *

# Exercises examples/ci/run-configs.sh, the loop every example pipeline calls, with a
# stub in place of the tool. The script is POSIX sh by design, so this suite runs it
# with `sh` — BusyBox's in the pinned image.

def script []: nothing -> string { $"($env.FILE_PWD | path dirname)/examples/ci/run-configs.sh" }

# The stub logs its arguments, writes the summary where asked as the tool does, and
# exits with the code named in the config file's `# stub-exit: N` line (0 when absent).
const STUB = '
echo "$*" >> "$STUB_LOG"
prev=""
for a in "$@"; do
    case "$a" in *.yaml) f="$a" ;; esac
    if [ "$prev" = "--summary-out" ]; then echo "{}" > "$a"; fi
    prev="$a"
done
code=$(sed -n "s/^# stub-exit: //p" "$f")
exit "${code:-0}"
'

# Run the script in a scratch workspace holding one config file per exit code.
def run-loop [codes: list<int>, ...args: string]: nothing -> record {
    let work = (mktemp -d -t "run-configs-XXXXXX")
    mkdir $"($work)/configs"
    for i in 0..<($codes | length) {
        $"# stub-exit: ($codes | get $i)\nrepositories: [r]\n" | save $"($work)/configs/c($i).yaml"
    }
    $STUB | save $"($work)/stub.sh"
    let log = $"($work)/log"
    "" | save $log
    let r = (with-env {NEXUS_CLEANUP: $"sh ($work)/stub.sh", STUB_LOG: $log, CONFIG_DIR: "configs", REPORT_DIR: "reports"} {
        cd $work
        ^sh (script) ...$args | complete
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
    { name: "any other argument is refused before anything runs", run: {||
        let r = (run-loop [0] "--keep" "1")
        assert equal $r.exit_code 2
        assert equal $r.calls []
    } }
]

def examples []: nothing -> string { $"($env.FILE_PWD | path dirname)/examples" }

run-suite "example pipelines" [
    { name: "GitLab: only the manual execute job passes --execute", run: {||
        let p = (open $"(examples)/gitlab-ci/nexus-cleanup.gitlab-ci.yml")
        let dry = ($p | get "nexus-cleanup:dry-run")
        let exec = ($p | get "nexus-cleanup:execute")
        assert not ($dry.script | any {|l| $l | str contains "--execute" })
        assert ($exec.script | any {|l| $l | str contains "run-configs.sh --execute" })
        assert ($exec.rules | all {|r| ($r.when? | default "") == "manual" })
        assert not ($exec.rules | any {|r| $r.if | str contains "schedule" })
        assert ($"(examples | path dirname)/($p.variables.CONFIG_DIR)" | path exists)
    } }
    { name: "Forgejo: only the dispatched execute step passes --execute", run: {||
        let p = (open $"(examples)/forgejo/nexus-cleanup.yml")
        let job = ($p.jobs.cleanup)
        let steps = ($job.steps | where {|s| ($s.run? | default "") | str contains "run-configs.sh" })
        assert equal ($steps | length) 2
        assert not (($steps | where name == "Dry run" | first).run | str contains "--execute")
        let exec = ($steps | where name == "Execute" | first)
        assert ($exec.run | str contains "--execute")
        assert ($exec.if | str contains "workflow_dispatch")
        assert ($"(examples | path dirname)/($job.env.CONFIG_DIR)" | path exists)
    } }
    { name: "Jenkins: --execute appears only in the Execute stage, after the input step", run: {||
        for f in ["Jenkinsfile.docker-plugin" "Jenkinsfile.sh"] {
            let text = (open --raw $"(examples)/jenkins/($f)")
            let parts = ($text | split row "stage('Execute')")
            assert equal ($parts | length) 2 $f
            assert not ($parts.0 | str contains "--execute") $f
            let exec = $parts.1
            assert (($exec | str index-of "input {") < ($exec | str index-of "run-configs.sh --execute")) $f
            assert ($exec | str contains "not { triggeredBy 'TimerTrigger' }") $f
        }
    } }
    { name: "every pipeline calls the loop script that exists", run: {||
        assert ($"(examples)/ci/run-configs.sh" | path exists)
        for f in (glob $"(examples)/{gitlab-ci,forgejo,jenkins}/*") {
            assert (open --raw $f | str contains "examples/ci/run-configs.sh") ($f | path basename)
        }
    } }
]
