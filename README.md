# nexus-proxy-cleanup

Deletes obsolete component versions from Nexus 3 **proxy** repositories, keeping the newest
`N` per component — per architecture and per distribution release. A Nushell script with no
runtime dependencies beyond Nushell itself, meant to run unattended in CI. It can also prune
dated build directories from a **raw hosted** repository, when you name it and opt in; see
[Raw hosted repositories](#raw-hosted-repositories).

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

## Getting started

The intended setup is a small private repository holding one [configuration
file](#configuration-files) per cleanup and one pipeline that runs them all. `init` writes that
repository, with every version pin matching the image you run it from:

```bash
mkdir nexus-cleanup-configs && cd nexus-cleanup-configs
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" \
  ghcr.io/bond-os/nexus-cleanup:0.1.0 init --ci gitlab --editor vscode
```

`--user` lets the container write your directory, as in [Who the container runs
as](#who-the-container-runs-as): under rootless Podman add `--userns=keep-id`, under rootless
Docker use `--user 0:0` instead. `init` needs no Nexus, no credentials and no `NEXUS_*`
variables, and lists every file it writes on stderr:

| File | Written |
|---|---|
| `.gitlab-ci.yml`, `.forgejo/workflows/nexus-cleanup.yml` or `Jenkinsfile` | the pipeline for `--ci` |
| `ci/run-configs.sh` | always: the loop the pipeline calls, one run per `configs/*.yaml` |
| `configs/example.yaml` | always: a starting configuration, with the schema modeline |
| `.editorconfig`, `.gitattributes` | always: UTF-8 and LF, so a Windows checkout cannot put CR into the pipeline's shell |
| `.vscode/settings.json`, `.vscode/extensions.json` | with `--editor vscode` |
| `.idea/jsonSchemas.xml` | with `--editor intellij` |

- **`--ci` is required**: `gitlab`, `forgejo`, `jenkins-docker` (the Docker Pipeline plugin) or
  `jenkins-sh` (plain `sh` steps calling `docker run`). [CI](#ci) describes how they differ.
- **`--editor vscode` and `--editor intellij`** may be given together; none is the default. Each
  maps the schema to `configs/*.yaml` and `configs/*.yml`, so a new file gets completion before
  it has a modeline. VS Code is pointed at Red Hat's YAML extension, which it recommends
  installing; IntelliJ-based IDEs need nothing extra.
- **A directory argument** writes there instead of the working directory — `/work`, your mounted
  directory, in the image — and creates it if needed.
- **Nothing is overwritten unasked.** If any file `init` would write already exists, it lists
  them all and writes nothing. `--force` overwrites exactly those files and touches nothing else;
  it does not merge. If you already have a `.vscode/settings.json`, leave out `--editor vscode`
  and copy the `yaml.schemas` entry from
  [`examples/gitlab/.vscode/settings.json`](examples/gitlab/.vscode/settings.json) into yours.
- **Commit `.idea/jsonSchemas.xml` explicitly.** `.idea/` is often in a global gitignore, which
  would keep the mapping from your colleagues: `git add -f .idea/jsonSchemas.xml`.

Then edit `configs/example.yaml`. Until it names a real repository it selects `replace-me`, so
the first pipeline run fails naming it rather than passing having cleaned nothing. Set the CI
variables or credentials the pipeline's header lists, commit and push.

`init` does not upgrade a repository it wrote earlier. To move to a newer release, bump the pins
by hand — the pipeline's image tag and the schema address in each file — or run the newer
image's `init --force` and read the diff before committing.

Each [`examples/<system>/`](examples/) directory is what `init --ci <system> --editor vscode
--editor intellij` writes, for reading before you run it. Its pinned lines also carry
`x-release-please` comments, which keep the examples current at each release and which `init`
does not write.

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
| *(positional)* | — | repositories to clean: proxies, or raw hosted with `--allow-hosted` |
| `--config` | — | read settings from a YAML file; flags override it, see [Configuration files](#configuration-files) |
| `--pattern` | — | select proxy repositories by glob instead |
| `--keep` | `1` | newest versions to retain per group |
| `--execute` | off | actually delete; omit for a dry run |
| `--allow-hosted` | off | allow named raw hosted repositories, see [below](#raw-hosted-repositories); deletes nothing without `--execute` |
| `--format` | `json` | `json` or `csv` |
| `--summary-out` | — | also write the aggregate here as JSON |
| `--version-scheme` | per format | force `generic`, `debian`, `rpm` or `date` |
| `--scope-from-path` | per format | regex with a `(?P<scope>…)` group |
| `--from-path` | — | regex with `(?P<name>…)` and `(?P<version>…)`: retain by path, see below |
| `--max-deletions` | `0` (off) | abort an executing run above this many |
| `--max-deletion-share` | `0` (off) | abort above this share of components |
| `--fail-on-skip` | off | exit non-zero if any group was skipped |
| `--require-cap` | off | refuse to run unless `--max-deletions` or `--max-deletion-share` is set |
| `--timeout` | `30sec` | per-request timeout |
| `--max-attempts` | `4` | attempts per retryable request |
| `--version` | — | print the tool version and exit; reads no configuration and contacts nothing |

You must name at least one repository or supply `--pattern`; there is no "all repositories"
default. `proxy` repositories are eligible, and so are `raw` hosted repositories that you name
while passing `--allow-hosted`. Naming any other repository — a group, a hosted repository of
another format, or a raw hosted one without the switch — is an error, not a silent skip.
`--pattern` only ever selects proxies.

## Configuration files

`--config <file>` reads a run's settings from a YAML file instead of flags. One file describes
one run, so a private repository can hold a file per target — `configs/yum.yaml`,
`configs/raw-builds.yaml` — and one pipeline that runs the tool once per file (see [CI](#ci)).
The regexes live in reviewed YAML rather than in shell quoting inside CI jobs.

```yaml
# x-release-please-start-version
# yaml-language-server: $schema=https://raw.githubusercontent.com/bond-os/nexus-cleanup/v0.2.0/schema/config.schema.json
# x-release-please-end
repositories: [raw-builds]
from-path: '^/(?P<name>some_dir|some_other_dir)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'
version-scheme: date
keep: 14
max-deletions: 200
```

```bash
nu nexus-cleanup.nu --config configs/raw-builds.yaml            # dry run
nu nexus-cleanup.nu --config configs/raw-builds.yaml --execute  # delete
```

Keys are the flag names without their dashes:

<!-- config-keys:start -->
| Key | Value | Flag |
|---|---|---|
| `url` | text | `--url` |
| `username` | text | `--username` |
| `repositories` | list of names | *(positional)* |
| `pattern` | text | `--pattern` |
| `keep` | integer | `--keep` |
| `timeout` | duration, e.g. `30sec`, `2min` | `--timeout` |
| `max-attempts` | integer | `--max-attempts` |
| `format` | `json` or `csv` | `--format` |
| `version-scheme` | `generic`, `debian`, `rpm` or `date` | `--version-scheme` |
| `scope-from-path` | regex | `--scope-from-path` |
| `from-path` | regex | `--from-path` |
| `fail-on-skip` | `true` / `false` | `--fail-on-skip` |
| `max-deletions` | integer | `--max-deletions` |
| `max-deletion-share` | number between 0 and 1 | `--max-deletion-share` |
| `summary-out` | path, relative to the working directory | `--summary-out` |
| `allow-hosted` | `true` / `false` | `--allow-hosted` |
<!-- config-keys:end -->

- **A flag overrides the file.** For `url` and `username` the environment sits in between:
  flag, then `NEXUS_URL` / `NEXUS_USERNAME`, then the file. That lets one set of files run
  against staging and production. Any repository selection on the command line — names or
  `--pattern` — replaces the file's `repositories` and `pattern` together.
- **Two keys are refused.** `execute`, whatever its value: deletion is asked for with the
  `--execute` flag and nothing else, so a scheduled job can never delete because someone edited a
  file. And `password`, as well as a `url` with credentials in it: those belong in
  `NEXUS_PASSWORD` or the CI system's secret store, never in a repository.
- **Parsing is strict.** An unknown key (`keeep: 3`), a value of the wrong type (`keep: "3"`,
  `fail-on-skip: yes`) or a file that is not a YAML mapping is a usage error naming the file and
  the key, raised before Nexus is contacted. A typo never falls back to a default.
- **Quote patterns and globs.** Single quotes make YAML process no escapes, so a regex arrives
  exactly as written: `from-path: '^/(?P<name>app)/…'`, `pattern: "yum-proxy-*"`.
- **`--require-cap`** refuses a run, dry or executing, unless `max-deletions` or
  `max-deletion-share` is set by the file or a flag. The example pipelines pass it to every run,
  so a file without a cap fails in the nightly dry run rather than when someone executes.

The file is always parsed as YAML, whatever its extension; JSON, being YAML, works too. The
report's summary records the path given to `--config` as `config_file`.

### Editor support

[`schema/config.schema.json`](schema/config.schema.json) is a JSON Schema for these files,
generated from the tool's own key table. Editors that use the YAML language server — VS Code
with Red Hat's YAML extension, among others — complete keys, show their descriptions and flag
a misspelt or refused key while you type, given the modeline at the top of the file:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bond-os/nexus-cleanup/vX.Y.Z/schema/config.schema.json
```

**Pin the tag of the release your pipeline runs** (`v0.1.0` with image `0.1.0`): release tags
never move, so the schema always matches the tool that reads the file. A JSON file can carry the
same address in a top-level `$schema` key, which the tool accepts and ignores. The schema is an
aid, not the authority: where it cannot express a rule exactly — whether a regex compiles, say —
it is looser than the tool, which still refuses the file.

A repository written by `init --editor vscode` or `--editor intellij` also maps the schema to
every file in `configs/` in the editor's project settings, so a new file is completed and
checked before it has a modeline; see [Getting started](#getting-started). Checked with VS Code
1.142.0 with Red Hat's YAML extension 2.0.0, IntelliJ IDEA 2026.2.3 and Rider 2026.2.3.1: keys
complete, and a misspelt key or `execute` is flagged with its description, in a file without a
modeline. The `.idea/jsonSchemas.xml` that `init` writes is identical to the one IntelliJ IDEA
2026.2.3 writes for the same mapping.

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

**What the `version` group captures decides what counts as one version.** Retention ranks the
distinct strings the group captures, so whether a respin's suffix is inside it or after it
changes what `--keep` counts:

| Pattern ends with | `20250103/` and `20250103-hotfix/` are | `--keep` counts |
|---|---|---|
| `(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/` | two versions, the respin newer | directories |
| `(?P<version>[0-9]{8})(?:[^0-9./][^/]*)?/` | one version, kept or deleted together | days |

**Keep anything that is not a date out of the match.** A directory such as `03012025-hotfix`
(day first) still matches `[0-9]{8}`, is not a real `YYYYMMDD` date, and makes its whole group
unorderable — nothing under that parent is deleted. Requiring a plausible year, month and day
leaves it outside the pattern instead, untouched like every other unmatched directory:

```
(?P<version>20[0-9]{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])(?:[^0-9./][^/]*)?)
```

A date the pattern cannot rule out, such as `20250231`, still makes its group unorderable.

**Asset paths begin with `/`.** Anchor the pattern as `^/…`; `^builds/` matches nothing, and
every component is reported `outside-pattern`.

## Raw hosted repositories

Build pipelines often publish into a **raw hosted** repository as dated directories —
`app/20261019/…`, `app/20261019-hotfix/…` — that nothing ever removes. Retention by path handles
that layout, and the tool cleans such a repository under three conditions:

- **`--allow-hosted`** (or `allow-hosted: true` in a configuration file) is given. It widens what
  can be selected, nothing more: without `--execute` the run is still a dry run.
- **The repository is named.** `--pattern` never selects a hosted repository, with or without the
  switch, so a glob cannot sweep in one created next year; a matching hosted repository is listed
  on stderr as excluded.
- **Its format is `raw`.** A hosted repository of any other format is refused: docker manifests,
  maven metadata, npm dist-tags and yum repodata all refer to other components, and deleting
  correctly there needs a study of each format that has not been done.

[`examples/configs/raw-hosted-builds.yaml`](examples/configs/raw-hosted-builds.yaml) is a
worked example:

```yaml
allow-hosted: true
repositories: [raw-hosted-builds]
from-path: '^/(?P<name>app)/(?P<version>[0-9]{8}(?:[^0-9./][^/]*)?)/'
version-scheme: date
keep: 10
max-deletions: 300
```

- **Hosted content is the only copy.** A deletion in a proxy costs a re-download; here it is
  permanent. Run the dry run first and read its records: each one carries the asset `path`, so
  the report lists exactly which URLs will stop working.
- **Without `--from-path` nothing is deleted.** Every raw component is then its own group, which
  the keep count retains. The tool proceeds — a dry run over the repository is a harmless
  inventory — and says so on stderr for each such repository.
- **A directory is deleted file by file.** Nexus has no transaction across components, so if
  some deletions fail, the files that remain stay, appear in the report with their error, and
  the run exits 1. The directory was due for deletion anyway; the next run retries what is left.
- **Dates decide, not upload times.** A directory backfilled today with an old date is as old
  as its name says, and the next run deletes it if it falls outside the keep window.
- **No cap is forced on you,** but set one: the example does, and `--require-cap` (which the
  example pipelines pass) refuses a file without it.

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

**In a proxy, a deletion is a cache eviction.** Anything deleted is re-fetchable from upstream —
which is what makes version-based cleanup safe there. The exception is an upstream that has
since removed the artifact. A raw hosted repository has no upstream; see
[Raw hosted repositories](#raw-hosted-repositories).

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

`init` writes one of four pipelines (see [Getting started](#getting-started)); each is meant to
be the pipeline of a private repository that holds the [configuration
files](#configuration-files). Each calls `ci/run-configs.sh`, which runs the tool once per
`*.yaml` file in `CONFIG_DIR` (`configs` by default). Adding a file needs no pipeline change.
They share one shape:

- **Every run is a dry run first**, on a nightly schedule, and keeps one report and summary per
  configuration file (`reports/<name>.dry-run.json`, `reports/<name>.dry-run.summary.json`) as
  build artifacts.
- **Deletion needs a person.** Only a run started by hand with an explicit execute switch
  deletes. A scheduled run never deletes.
- **Every file needs a deletion cap.** The loop passes `--require-cap`, so a file without
  `max-deletions` or `max-deletion-share` fails the dry run.
- **One failing file does not hide the others.** The loop runs every file and ends with the
  first exit code other than 0 and 4; otherwise 4 if any file had skipped groups; otherwise 0.
- **Credentials come from the CI system's secret store** as `NEXUS_USERNAME` and
  `NEXUS_PASSWORD`, never from a command line.

Keep the dry run and the deletion separate. A job that deletes on a schedule is a job nobody
reads the output of.

| CI system | File | Runs in | Approval before deleting |
|---|---|---|---|
| GitLab CI (`--ci gitlab`) | [`.gitlab-ci.yml`](examples/gitlab/.gitlab-ci.yml) | the release image, entrypoint cleared | a blocked manual job |
| Forgejo Actions (`--ci forgejo`) | [`.forgejo/workflows/nexus-cleanup.yml`](examples/forgejo/.forgejo/workflows/nexus-cleanup.yml) | a node image; the release tag cloned, Nushell installed by checksum | none; each file's cap is the guard |
| Jenkins, Docker Pipeline plugin (`--ci jenkins-docker`) | [`Jenkinsfile`](examples/jenkins-docker/Jenkinsfile) | the release image, entrypoint cleared | an `input` step |
| Jenkins, plain `sh` (`--ci jenkins-sh`) | [`Jenkinsfile`](examples/jenkins-sh/Jenkinsfile) | the release image via `docker run` | an `input` step |

Every pipeline pins an exact release (`ghcr.io/bond-os/nexus-cleanup:0.1.0`, or the tag `v0.1.0`
for Forgejo): the release whose `init` wrote it. Bump the pin deliberately, after reading
`CHANGELOG.md`, together with the schema address in your configuration files. The links above
go to the rendered examples, one complete repository per CI system under `examples/`.

Two container details matter. A CI system that runs a shell script inside the image needs its
entrypoint cleared (`entrypoint: [""]` in GitLab, `args '--entrypoint='` for the Jenkins plugin);
the tool is then on `PATH` as `nexus-cleanup`. And Forgejo runs JavaScript actions such as
`upload-artifact` inside the job container, which the release image cannot do because it has no
node — hence the node image there.

Skipped groups (exit 4, with `fail-on-skip`) and failed deletions (exit 1) are surfaced as
warnings where the CI system has them: allowed failure in GitLab, unstable in Jenkins, a passing
dry-run step in Forgejo.

## Development

```bash
nu tests/run-tests.nu                        # hermetic; never contacts a Nexus
nu tools/record-fixtures.nu --max-pages 1 …  # re-record fixtures from a live instance
```

See `AGENTS.md` for conventions and for the standing decisions behind the design.

## License

MIT; see `LICENSE`.
