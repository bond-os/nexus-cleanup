#!/bin/sh
# Runs nexus-cleanup once per configuration file, so a pipeline never has to list
# its files: add configs/<name>.yaml and the next run picks it up.
#
#   sh ci/run-configs.sh              dry run of every file
#   sh ci/run-configs.sh --execute    delete, for every file
#
# Every run gets --require-cap, so a file without max-deletions or
# max-deletion-share fails in the scheduled dry run, not when someone executes.
# A failing file does not stop the others. The job ends with the first exit code
# other than 0 and 4; otherwise 4 if any file had skipped groups; otherwise 0.
#
# CONFIG_DIR    directory of *.yaml files      (default: configs)
# REPORT_DIR    where reports are written      (default: reports)
# NEXUS_CLEANUP command that runs the tool     (default: nexus-cleanup)

set -u

config_dir="${CONFIG_DIR:-configs}"
report_dir="${REPORT_DIR:-reports}"
tool="${NEXUS_CLEANUP:-nexus-cleanup}"

execute=""
mode="dry-run"
if [ $# -gt 1 ]; then
    echo "run-configs: the only argument is --execute" >&2
    exit 2
fi
case "${1:-}" in
    "") ;;
    --execute) execute="--execute"; mode="execute" ;;
    *) echo "run-configs: unknown argument '$1'; the only argument is --execute" >&2; exit 2 ;;
esac

# Sorted by the shell's glob expansion. A pattern that matches nothing stays
# literal, so check for it rather than run the tool on a file that is not there.
set -- "$config_dir"/*.yaml
if [ ! -e "$1" ]; then
    echo "run-configs: no configuration file (*.yaml) in $config_dir" >&2
    exit 2
fi

mkdir -p "$report_dir"
first_failure=0
skipped=0
for file in "$@"; do
    name=$(basename "$file" .yaml)
    echo "run-configs: $file ($mode)" >&2
    # $tool and $execute are unquoted on purpose: the tool may be a command with
    # arguments, and an empty $execute must vanish.
    $tool --config "$file" --require-cap $execute \
        --summary-out "$report_dir/$name.$mode.summary.json" \
        > "$report_dir/$name.$mode.json"
    code=$?
    case "$code" in
        0) ;;
        4) skipped=1; echo "run-configs: $file: some groups were skipped" >&2 ;;
        *) echo "run-configs: $file: exited $code" >&2
           if [ "$first_failure" -eq 0 ]; then first_failure=$code; fi ;;
    esac
done

if [ "$first_failure" -ne 0 ]; then exit "$first_failure"; fi
if [ "$skipped" -ne 0 ]; then exit 4; fi
exit 0
