#!/usr/bin/env bash
# Smoke-checks a locally loaded nexus-cleanup image. Hermetic: no network, no Nexus.
# Used by pull-request CI and by the release job before anything is pushed.
#
#   .github/scripts/image-smoke.sh IMAGE EXPECTED_VERSION
#   CONTAINER_ENGINE=podman .github/scripts/image-smoke.sh IMAGE EXPECTED_VERSION
#
# CONTAINER_ENGINE is `docker` (default, rootful) or `podman` (rootless). The
# engine decides how a caller-owned workspace is mapped into the container.
#
# Exits non-zero on the first failed check.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 IMAGE EXPECTED_VERSION" >&2
  exit 2
fi
image=$1
expected=$2
engine=${CONTAINER_ENGINE:-docker}

# Runs the container as the caller, so that a workspace only the caller can write
# is writable inside. Rootful Docker takes the caller's uid as is. Rootless Podman
# maps the caller to container root, so the same uid inside the user namespace is
# someone else. keep-id maps the caller to their own uid, but on its own runs the
# image's USER; --user is still needed to run as the caller.
case "$engine" in
  docker) as_caller=(--user "$(id -u):$(id -g)") ;;
  podman) as_caller=(--userns=keep-id --user "$(id -u):$(id -g)") ;;
  *) echo "CONTAINER_ENGINE must be docker or podman, not '$engine'" >&2; exit 2 ;;
esac

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok    $*"; }

# Runs the container with no environment beyond what is passed, capturing stdout,
# stderr and the exit code separately. Never with -t: a TTY merges the streams.
out=$(mktemp) err=$(mktemp) work=$(mktemp -d)
trap 'rm -rf "$out" "$err" "$work"' EXIT
run() {
  set +e
  "$engine" run --rm "$@" >"$out" 2>"$err"
  code=$?
  set -e
}

# 1. The default entrypoint prints the version.
run "$image" --version
[ "$code" -eq 0 ] || fail "--version exited $code: $(cat "$err")"
[ "$(cat "$out")" = "$expected" ] || fail "--version printed '$(cat "$out")', expected '$expected'"
pass "--version prints $expected"

# 2. No selection is a usage error, with nothing on stdout.
run "$image"
[ "$code" -eq 2 ] || fail "no arguments exited $code, expected 2"
[ ! -s "$out" ] || fail "no arguments wrote to stdout: $(cat "$out")"
pass "no arguments exits 2 with empty stdout"

# 3. The image sets nothing that changes behaviour: the tool sees no Nexus config.
grep -q 'NEXUS_URL' "$err" || fail "usage error does not name NEXUS_URL: $(cat "$err")"
pass "the image sets no NEXUS_* configuration"

# 4. Entrypoint cleared, invoked by name from a shell, as GitLab and Jenkins do.
run --entrypoint "" "$image" sh -c 'nexus-cleanup --version'
[ "$code" -eq 0 ] && [ "$(cat "$out")" = "$expected" ] \
  || fail "nexus-cleanup from a shell: exit $code, stdout '$(cat "$out")'"
pass "nexus-cleanup on PATH behaves like the entrypoint"

# 5. A workspace mounted at the working directory does not hide the tool, and
#    relative output paths land in it.
chmod 0777 "$work"
run -v "$work:/work" "$image" --version
[ "$code" -eq 0 ] && [ "$(cat "$out")" = "$expected" ] || fail "--version with /work mounted: exit $code"
run -v "$work:/work" --entrypoint nu "$image" -c '"probe" | save probe.txt'
[ -f "$work/probe.txt" ] || fail "a relative path did not land in the mounted /work"
pass "a mount at /work leaves the tool intact and receives relative output"

# 6. Arguments arrive intact through the launcher: spaces, quotes, the empty
#    string, and an unknown flag reported by the tool itself.
run "$image" --url 'http://127.0.0.1:9' --keep 0 'repo with spaces' 'a"b' ''
[ "$code" -eq 2 ] || fail "invalid --keep through the launcher exited $code, expected 2"
grep -q -- '--keep' "$err" || fail "the usage error does not name --keep: $(cat "$err")"
run "$image" --no-such-flag
[ "$code" -ne 0 ] || fail "an unknown flag was accepted"
grep -q -- 'no-such-flag' "$err" || fail "the unknown flag is not named: $(cat "$err")"
[ ! -s "$out" ] || fail "an unknown flag wrote to stdout"
pass "flags and awkward arguments pass through the launcher unchanged"

# 6b. Byte-exact round trip: swap the tool for a probe that echoes its arguments
#     and exits 7, then call the real launcher.
probe=$(mktemp -d)
# shellcheck disable=SC2016 # Nushell source, expanded by nu, not the shell
printf '%s\n' 'def --wrapped main [...args] { print --stderr "probe-stderr"; print ($args | to json --raw); exit 7 }' \
  > "$probe/nexus-cleanup.nu"
chmod -R a+rX "$probe"
run -v "$probe:/opt/nexus-cleanup:ro" "$image" --execute --keep=2 'repo with spaces' 'a"b' '' "it's"
rm -rf "$probe"
[ "$code" -eq 7 ] || fail "the probe's exit code 7 came back as $code"
[ "$(cat "$out")" = '["--execute","--keep=2","repo with spaces","a\"b","","it'"'"'s"]' ] \
  || fail "arguments arrived as $(cat "$out")"
[ "$(cat "$err")" = "probe-stderr" ] || fail "stderr was not passed through separately: $(cat "$err")"
pass "arguments, stdout, stderr and the exit code round-trip through the launcher exactly"

# 7. --help is the tool's own help, not the launcher's.
run "$image" --help
[ "$code" -eq 0 ] || fail "--help exited $code"
grep -q -- '--execute' "$out" || fail "--help does not show the tool's flags"
pass "--help shows the tool's help"

# 8. Importing the module is inert.
run --entrypoint nu "$image" -c 'use /opt/nexus-cleanup/nexus-cleanup'
[ "$code" -eq 0 ] && [ ! -s "$out" ] && [ ! -s "$err" ] || fail "importing the module was not inert"
pass "importing the module prints nothing"

# 9. The image holds the tool and nothing else from the repository.
run --entrypoint nu "$image" -c 'ls /opt/nexus-cleanup | get name | path basename | sort | str join ","'
[ "$(cat "$out")" = "nexus-cleanup,nexus-cleanup.nu" ] || fail "/opt/nexus-cleanup holds: $(cat "$out")"
run --entrypoint nu "$image" -c 'ls -a /work | length'
[ "$(cat "$out")" = "0" ] || fail "/work is not empty"
pass "only the entrypoint and the module are installed; /work is empty"

# 10. The version label agrees with the tool.
label=$("$engine" image inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$image")
[ "$label" = "$expected" ] || fail "version label is '$label', expected '$expected'"
pass "org.opencontainers.image.version is $expected"

# 11. The image declares a numeric, non-root user: Kubernetes' runAsNonRoot cannot
#     verify a named one and refuses to start the pod.
user=$("$engine" image inspect --format '{{ .Config.User }}' "$image")
[[ "$user" =~ ^([0-9]+):[0-9]+$ ]] || fail "image user is '$user', expected a numeric uid:gid"
[ "${BASH_REMATCH[1]}" -ne 0 ] || fail "image user is root ($user)"
pass "the image runs as $user"

# 12. Any uid works, with group 0 as OpenShift assigns it, a read-only root
#     filesystem, no capabilities and no privilege escalation.
hardened=(--user 12345:0 --read-only --cap-drop ALL --security-opt no-new-privileges)
run "${hardened[@]}" "$image" --version
[ "$code" -eq 0 ] && [ "$(cat "$out")" = "$expected" ] \
  || fail "--version as an arbitrary uid: exit $code, stdout '$(cat "$out")', stderr '$(cat "$err")'"
run "${hardened[@]}" "$image"
[ "$code" -eq 2 ] || fail "no arguments as an arbitrary uid exited $code, expected 2: $(cat "$err")"
pass "an arbitrary uid runs the tool on a read-only root with no capabilities"

# 13. A workspace only the caller can write (mktemp -d is 0700) receives the
#     summary when the container runs as the caller. Written through the same
#     `cleanup emit` that --summary-out uses; a real run would need a Nexus.
ws=$(mktemp -d)
# shellcheck disable=SC2016 # Nushell source, expanded by nu, not the shell
run "${as_caller[@]}" -v "$ws:/work" --entrypoint nu "$image" -c '
  use /opt/nexus-cleanup/nexus-cleanup/run.nu *
  use /opt/nexus-cleanup/nexus-cleanup/report.nu *
  let summary = (report summary [] {mode: "dry-run", started_at: "", finished_at: "",
    nexus_url: "", repositories: [], keep: 1})
  cleanup emit {summary: $summary, records: []} json summary.json'
owned=no
[ -O "$ws/summary.json" ] && owned=yes
rm -rf "$ws"
[ "$code" -eq 0 ] || fail "writing the summary as the caller exited $code: $(cat "$err")"
[ "$owned" = yes ] || fail "the summary is missing from the workspace or not owned by the caller"
pass "a caller-owned workspace receives the summary, owned by the caller (${as_caller[*]})"

echo "image smoke check passed: $image"
