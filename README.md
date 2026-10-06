# nexus-proxy-cleanup

Deletes obsolete component versions from Nexus 3 **proxy** repositories, keeping the newest
`N` per component — per architecture and per distribution release. A Nushell script with no
runtime dependencies beyond Nushell itself, meant to run unattended in CI.

Proxy repositories in Nexus grow without bound: the built-in cleanup policies are age and
usage based, not version based, so a proxy that has mirrored a busy upstream for a year holds
hundreds of superseded versions per component.

**Dry run is the default.** There is no `--dry-run` flag; the safe mode is the one you get by
forgetting a flag. Nothing is ever deleted unless you pass `--execute`.

## Quick start

```bash
export NEXUS_URL=https://nexus.example.com
export NEXUS_USERNAME=cleanup
export NEXUS_PASSWORD=…

# See what would happen — no deletions, JSON report on stdout
nu nexus-cleanup.nu --pattern 'yum-proxy-*'

# Do it, keeping the two newest per group, refusing to delete more than 500
nu nexus-cleanup.nu --pattern 'yum-proxy-*' --keep 2 --max-deletions 500 --execute
```

### In a container

Each release is published as a multi-platform image (`linux/amd64`, `linux/arm64`,
`linux/arm/v7`). Its entrypoint is the tool, so flags follow the image name directly:

```bash
docker run --rm -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD \
  ghcr.io/bond-os/nexus-cleanup:0.1.0 --pattern 'yum-proxy-*' > report.json
```

**Pin an exact version** (`0.1.0`), or a digest (`@sha256:…`) for full reproducibility, and bump
it deliberately after reading `CHANGELOG.md`. Each release also moves an `X.Y` tag (`0.1`) to its
newest patch. There is deliberately **no `latest`**: a scheduled cleanup on a floating tag would
pick up new deletion behaviour that nobody has read about.

The working directory is an empty `/work`; mount your workspace there and relative paths such as
`--summary-out summary.json` land in it. The tool itself lives in `/opt/nexus-cleanup`, so the
mount cannot hide it. `--user` lets the container write your directory. For rootless runtimes,
see [Who the container runs as](#who-the-container-runs-as).

```bash
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD \
  ghcr.io/bond-os/nexus-cleanup:0.1.0 --pattern 'yum-proxy-*' --summary-out summary.json > report.json
```

CI systems that run a shell script inside the image (GitLab, the Jenkins Docker Pipeline plugin)
clear the entrypoint and call the tool by name — it is on `PATH` as `nexus-cleanup` and behaves
exactly like the entrypoint:

```bash
docker run --rm --entrypoint "" -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD \
  ghcr.io/bond-os/nexus-cleanup:0.1.0 sh -c "nexus-cleanup --pattern 'yum-proxy-*'"
```

Every image carries a build provenance attestation tying it to the commit and workflow run that
built it:

```bash
gh attestation verify oci://ghcr.io/bond-os/nexus-cleanup:0.1.0 --repo bond-os/nexus-cleanup
```

To run an unreleased revision, use the stock Nushell image with a checkout mounted — that
image's entrypoint is `nu`, so the script path comes first:

```bash
docker run --rm -v "$PWD:/work" -w /work -e NEXUS_URL -e NEXUS_USERNAME -e NEXUS_PASSWORD \
  ghcr.io/nushell/nushell:0.115.1-alpine \
  nexus-cleanup.nu --pattern 'yum-proxy-*'
```

Never pass `-t`: a TTY merges stderr into stdout, and stdout is the report.

#### Who the container runs as

The image runs as uid/gid `1000:1000`, declared numerically. The tool needs no root, no
capabilities and no writable path except the files you ask it to write, so it also runs on a
read-only root filesystem and under any uid the runtime assigns.

- **Kubernetes:** a pod with `runAsNonRoot: true` (required by the "restricted" Pod Security
  Standard) starts it without setting `runAsUser`.
- **OpenShift:** the arbitrary uid with gid 0 that `restricted-v2` assigns works as is.
- **GitLab runners** (Docker, rootless Podman or Kubernetes executor) hand the job a
  world-writable build directory, so no flag is needed.

When you **mount a workspace yourself**, the uid inside the container must be able to write it.
The right flag depends on the runtime:

| Runtime | Add to `docker run` / `podman run` | Files in the workspace end up owned by |
|---|---|---|
| Docker (rootful) | `--user "$(id -u):$(id -g)"` | you |
| Podman (rootless) | `--userns=keep-id --user "$(id -u):$(id -g)"` | you |
| Docker (rootless) | `--user 0:0` | you (container root *is* your user) |

Under a rootless runtime, `--user "$(id -u):$(id -g)"` **on its own** is wrong. The user
namespace maps your host uid to container root, so the same number inside the container is an
unrelated subordinate uid that cannot write your workspace. Podman's `--userns=keep-id` maps
your uid to itself, but without `--user` the container still runs as the image's uid 1000.
That only works if your own uid happens to be 1000.

## Configuration

| Setting | Environment | Flag |
|---|---|---|
| Nexus base URL | `NEXUS_URL` | `--url` |
| Username | `NEXUS_USERNAME` | `--username` |
| Password | `NEXUS_PASSWORD` | `--password` |

A flag overrides the environment. Everything is validated before a single component is
enumerated. Credentials never appear in the report, in diagnostics, or in any error message.

| Flag | Default | Meaning |
|---|---|---|
| *(positional)* | — | proxy repositories to clean |
| `--pattern` | — | select proxy repositories by glob instead |
| `--keep` | `1` | newest versions to retain per group |
| `--execute` | off | actually delete; omit for a dry run |
| `--format` | `json` | `json` or `csv` |
| `--summary-out` | — | also write the aggregate here as JSON |
| `--version-scheme` | per format | force `generic`, `debian`, `rpm` or `date` |
| `--scope-from-path` | per format | regex with a `(?P<scope>…)` group |
| `--from-path` | — | regex with `(?P<name>…)` and `(?P<version>…)`: retain by path, see below |
| `--max-deletions` | `0` (off) | abort an executing run above this many |
| `--max-deletion-share` | `0` (off) | abort above this share of components |
| `--fail-on-skip` | off | exit non-zero if any group was skipped |
| `--timeout` | `30sec` | per-request timeout |
| `--max-attempts` | `4` | attempts per retryable request |
| `--version` | — | print the tool version and exit; reads no configuration and contacts nothing |

You must name at least one repository or supply `--pattern`; there is no "all repositories"
default. Only `proxy` repositories are eligible — naming a hosted or group repository is an
error, not a silent skip.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | completed, but at least one deletion failed |
| 2 | usage or configuration error (nothing was enumerated) |
| 3 | Nexus unreachable or enumeration failed (nothing was deleted) |
| 4 | groups were skipped and `--fail-on-skip` was given |
| 5 | the deletion cap was exceeded; nothing was deleted |

## How retention is decided

Components are grouped by **`(repository, scope, namespace, name, variant)`** and the newest
`N` of each group are kept.

**Scope** separates distribution releases and repository sections, which the component
metadata does not distinguish on its own:

| Format | Scope |
|---|---|
| yum | the asset's directory (`/releases/44/…` never competes with `/updates/44/…`) |
| apt | the repository's configured `apt.distribution` |
| everything else | a single implicit scope |

**Variant** separates architectures:

| Format | Variant |
|---|---|
| apt, yum | the component's `group` field (`amd64`, `noarch`), falling back to the filename |
| docker | `docker.architecture` for a single-arch manifest; `multiarch` for a manifest list or OCI index |
| everything else | the implicit variant `*` |

`multiarch` is deliberately not spelled `all`, because in Debian `all` is a real architecture.

**Ordering is strict.** Versions are compared with the comparator for the repository's format
— `generic` (semver-ish), `debian` (dpkg semantics, including epochs and `~`), or `rpm`
(`rpmvercmp`, including `~` and `^`). If any version in a group cannot be parsed, or two
versions compare equal, the whole group is skipped and reported. There is no fallback to
timestamps or to lexicographic order: a confident wrong ordering deletes the wrong artifact.

A group holding `N` or fewer components is kept without being ordered at all, so formats with
no usable version (`raw`, whose components have an empty version) produce no skip noise.

## Retention by path

Some repositories keep what matters for retention in the path rather than in component
metadata — typically a `raw` repository of dated build directories. `--from-path` takes a regex
with a `(?P<name>…)` and a `(?P<version>…)` group; for every component whose asset path
matches, the extracted name becomes the group and the extracted version is what gets ordered.

Keep the newest 14 date directories under each of two parents, and never touch the
semver-named directories next to them:

```bash
nu nexus-cleanup.nu raw-builds \
  --from-path '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/' \
  --version-scheme date --keep 14
```

- **Anything the pattern does not match is never deleted.** It is reported as `keep` with reason
  `outside-pattern` and takes no part in retention — here the `3.2.4.24-something` directories,
  files directly under `some_dir/`, and every component of any other targeted repository.
- **A directory is one item.** `--keep 14` keeps the 14 newest distinct versions; every file
  under them survives, however many there are and however deeply nested.
- **Name the parents explicitly.** `(?P<name>[^/]+)` would sweep date-named directories under
  *any* top-level directory into retention.
- **The character after the eighth digit must be neither a digit nor a dot.** That is what keeps
  an 8-digit semver major such as `12345678.0.1` out of the match.

The `date` scheme reads `YYYYMMDD` — which must be a real calendar date — optionally followed by
a suffix that does not start with a digit. Dates order chronologically; within one day the bare
date comes first and respins follow in natural order (`20250103` < `20250103-hotfix` <
`20250103-hotfix2` < `20250103-hotfix10`). A matched directory that is not a real date
(`20250229`) makes its parent's group unorderable, so nothing under that parent is deleted.
`date` is never chosen automatically; pass `--version-scheme date`.

## The report

Stdout carries the report and nothing else; diagnostics go to stderr. JSON is one document
with `summary` and `records`; CSV is the record table alone, with the aggregate available via
`--summary-out`.

Each record carries `repository, format, scope, group, name, variant, version, component_id,
decision, reason, rank, size_bytes, last_modified, deleted, error, path`. Fields that do not
apply are present and empty rather than omitted. New fields are only ever appended, so CSV
column positions never move; `path` was added last.

The `summary` block (and the `--summary-out` file) ends with `tool_version`, the version of the
tool that produced the report — the same string `--version` prints. Keep it with archived reports:
it is what tells you which release made a given deletion decision. Summary fields, like record
fields, are only ever appended.

`decision` is one of `keep`, `delete`, `skip`. `reason` is one of:

| Reason | Meaning |
|---|---|
| `group-within-keep` | the group holds no more than `--keep` components, so nothing could be deleted |
| `within-keep-window` | ranked inside the retention window |
| `superseded` | a newer version exists in the same group |
| `group-unorderable` | some version in the group could not be parsed |
| `group-ambiguous` | two distinct components compare as the same version |
| `outside-pattern` | `--from-path` was given and this component's path does not match it; never deleted |

## Things worth knowing

**Freed space appears only after blob compaction.** Deleting components removes them from the
repository, but the disk is not reclaimed until Nexus' own "Compact blob store" task runs.

**A deletion is a cache eviction.** These are proxy repositories, so anything deleted is
re-fetchable from upstream — which is what makes version-based cleanup safe here. The
exception is an upstream that has since removed the artifact.

**apt repositories carry a residual risk.** A Nexus apt proxy is pinned to one suite via
`apt.distribution`, and clients only learn pool paths from that suite's index, so in normal
use a repository holds one suite. But `enforceDistribution` defaults to false, so a client
that requests another suite's pool path directly can leave foreign-suite files in the cache
that nothing in the component metadata distinguishes. Recovering the true suite would mean
parsing compressed `Packages` indexes, which is not possible without an external
decompressor. Use `--keep` above 1 and a deletion cap on such repositories.

**Older Nexus versions.** Response shapes are taken from Nexus 3.96 Community Edition, but
nothing reads or branches on the version: unknown fields are ignored, documented fields may be
absent, and paging follows the continuation token alone. On an instance that exposes fewer
attributes, the variant layer degrades to filename parsing or the implicit variant, and the
report shows which happened.

## CI

Complete pipelines live in `examples/`. They share one shape:

- **Every run is a dry run first**, on a nightly schedule, and keeps the report and summary as
  build artifacts.
- **Deletion needs a person.** Only a run started by hand with an explicit execute switch
  deletes, and only with a positive `--max-deletions`. A scheduled run never deletes.
- **Credentials come from the CI system's secret store** as `NEXUS_USERNAME` and
  `NEXUS_PASSWORD`, never from a command line.

Keep the dry run and the deletion separate. A job that deletes on a schedule is a job nobody
reads the output of.

| CI system | File | Runs in | Approval before deleting |
|---|---|---|---|
| GitLab CI | `examples/gitlab-ci/nexus-cleanup.gitlab-ci.yml` | the release image, entrypoint cleared | a blocked manual job |
| Forgejo Actions | `examples/forgejo/nexus-cleanup.yml` | a node image; the release tag cloned, Nushell installed by checksum | none; the cap is the guard |
| Jenkins, Docker Pipeline plugin | `examples/jenkins/Jenkinsfile.docker-plugin` | the release image, entrypoint cleared | an `input` step |
| Jenkins, plain `sh` | `examples/jenkins/Jenkinsfile.sh` | the release image via `docker run` | an `input` step |

Every example pins an exact release (`ghcr.io/bond-os/nexus-cleanup:0.1.0`, or the tag `v0.1.0`
for Forgejo) and needs nothing from this repository in the consumer's checkout. Bump the pin
deliberately, after reading `CHANGELOG.md`.

Two container details matter. A CI system that runs a shell script inside the image needs its
entrypoint cleared (`entrypoint: [""]` in GitLab, `args '--entrypoint='` for the Jenkins plugin);
the tool is then on `PATH` as `nexus-cleanup`. And Forgejo runs JavaScript actions such as
`upload-artifact` inside the job container, which the release image cannot do because it has no
node — hence the node image there.

Skipped groups (exit 4, with `--fail-on-skip`) and failed deletions (exit 1) are surfaced as
warnings where the CI system has them: allowed failure in GitLab, unstable in Jenkins.

## Development

```bash
nu tests/run-tests.nu                        # hermetic; never contacts a Nexus
nu tools/record-fixtures.nu --max-pages 1 …  # re-record fixtures from a live instance
```

See `AGENTS.md` for conventions and for the standing decisions behind the design.

## License

MIT; see `LICENSE`.
