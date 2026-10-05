# AGENTS.md

Conventions for `nexus-proxy-cleanup` — a Nushell tool that deletes obsolete component
versions from Nexus 3 **proxy** repositories, keeping the newest N per component and
architecture.

This file takes precedence over the global conventions where the two differ. Deliberate
exceptions are recorded below **with their rationale** — do not "fix" them.

## Runtime

The repository holds code in three areas, and the language rule differs between them:

| Area | What | Rule |
|---|---|---|
| **The tool** | `nexus-cleanup.nu`, `nexus-cleanup/`, everything inside the container image | Nushell only, no external binaries (below) |
| **Tests and dev tools** | `tests/`, `tools/` | Nushell — they exercise the tool and share its runtime |
| **Maintenance automation** | release, commit checks, image build and smoke check (`.github/`, release and commitlint config) | established third-party tools, *configured rather than written*; shell only as glue around them |

The Nushell-only rule exists so that the tool runs from an image holding nothing but Nushell. It
does not extend to the machinery that releases the tool: reimplementing a release bot or a commit
linter in Nushell would be code to maintain with no runtime benefit. Conversely, nothing from the
maintenance area may enter the image or become a runtime dependency of the tool.

For the tool, tests and dev tools:

- **Nushell only.** Version floor **0.115.1**. Pinned CI image:
  `ghcr.io/nushell/nushell:0.115.1-alpine`.
- The floor is set by features the tool relies on: `sort-by --custom` with a two-argument
  comparator closure, and `http get`/`http delete` with `--full`, `--allow-errors`,
  `--max-time` and `--user`/`--password`.
- No external binaries at runtime — no `curl`, no `jq`, no Python. A complete run must work in
  an image that holds only Nushell and its standard library.
- Nushell breaks compatibility between minor releases. Raising the floor means re-running the
  suite in the new image, not just bumping a number.

## Layout

```
nexus-cleanup.nu          # entrypoint: flags -> module calls -> exit code, nothing else
nexus-cleanup/
  mod.nu                  # public surface
  config.nu               # env + flag resolution and validation
  api.nu                  # client record, retry, pagination, repo/component/delete
  variants.nu             # per-format architecture/variant adapters
  versions.nu             # generic / debian / rpm / date comparators
  scopes.nu               # per-format scope (release / section) derivation
  paths.nu                # --from-path matching: name and version from the asset path
  policy.nu               # grouping, ordering, keep/delete/skip decisions
  report.nu               # record schema, aggregate, json/csv encoding
  run.nu                  # orchestration: enumerate, plan, delete, emit
  version.nu              # VERSION; rewritten by release-please, never by hand
tools/
  record-fixtures.nu      # development only; records redacted fixtures from a live Nexus
examples/                 # CI pipelines: dry run on schedule, deletion only by hand
  gitlab-ci/
  forgejo/
  jenkins/                # Docker Pipeline plugin and plain `sh` variants
tests/
  fixtures/<format>/      # recorded, redacted Nexus API responses
  test-*.nu               # std assert tests
  run-tests.nu            # runner
Containerfile             # release image: COPY only, no RUN
.dockerignore             # allow-list: only the tool and packaging/ reach the build
packaging/
  nexus-cleanup           # launcher on PATH and image ENTRYPOINT
.github/
  workflows/              # tests (+ image check), commits, release
  scripts/image-smoke.sh  # hermetic image checks, shared by PR CI and release
release-please-config.json, .release-please-manifest.json, .commitlintrc.yaml
```

`tools/` is development-time only. The shipped module never reads it and the container image
does not need it.

In the image the tool lives in `/opt/nexus-cleanup`, the launcher in `/usr/local/bin`, and the
working directory `/work` is empty — CI systems mount their workspace there, which would hide
anything installed in it. The launcher `exec`s `nu /opt/nexus-cleanup/nexus-cleanup.nu` with its
arguments passed through by `def --wrapped`; do not replace it with a symlink, because Nushell
resolves the entrypoint's relative `use ./nexus-cleanup/…` against the symlink's directory and
fails to find the module.

## Tests

```bash
nu tests/run-tests.nu
```

Runs every `tests/test-*.nu`; non-zero exit on failure. The suite is hermetic — it never
contacts a Nexus. Run it inside the pinned image before calling work done.

Importing the module must stay inert: `nu -c 'use nexus-cleanup'` makes no request and prints
nothing.

## Commits and merging

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) and are
checked by commitlint with the stock `@commitlint/config-conventional` preset
(`.commitlintrc.yaml`) — every commit of every pull request, in CI. The preset is used unmodified
so the same check runs anywhere without project-specific rules to remember.

Pull requests land on `main` by **rebase merge only**; squash and merge commits are disabled.
This is deliberate: release-please derives versions and the changelog from the commits on
`main`, so each commit must reach `main` exactly as the check validated it. Squashing would
collapse a branch's `feat:`/`fix:`/`docs:` commits into one changelog line chosen at merge time.
Keep commits atomic and reword them before review rather than after.

The CI check is the gate (`.github/workflows/commits.yml`, which pins exact commitlint versions;
the hook below uses the same ones). A local hook is optional:

```bash
printf '#!/bin/sh\nexec npx --yes -p @commitlint/cli@21.2.3 -p @commitlint/config-conventional@21.2.3 commitlint --edit "$1"\n' > .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

## Releases

Releases are cut by [release-please](https://github.com/googleapis/release-please) from the
commits on `main` (`release-please-config.json`, `.release-please-manifest.json`,
`.github/workflows/release.yml`).

```
merge to main --> release-please opens/updates the release PR (version + CHANGELOG.md)
                     | maintainer merges the release PR
                     v
                  tag vX.Y.Z + GitHub Release        (same workflow run)
                     v
                  tests --> build, smoke, push X.Y.Z and X.Y --> attest
```

- **Versioning.** Conventional Commits decide the bump. Below 1.0 a breaking change bumps the
  minor (`bump-minor-pre-major`); the first release is `0.1.0` (`initial-version`). Do not hand-
  edit versions: `nexus-cleanup/version.nu` is the single source, rewritten by release-please via
  its `x-release-please-version` marker. The tool's `--version`, the report's `tool_version` and
  the image's version label all read it, and the release job refuses to publish if it disagrees
  with the release.
- **The changelog shows behaviour.** `feat`, `fix`, `perf` and `revert` are listed; `docs`,
  `test`, `ci`, `chore`, `refactor`, `build` and `style` are hidden. Operators read the changelog
  to decide whether to move a pinned version.
- **Image tags are `X.Y.Z` and `X.Y` — never `latest`.** A scheduled cleanup on a floating tag
  would silently pick up new deletion behaviour. `X.Y` only ever moves to a patch release, which
  below 1.0 means fixes only. Do not add `latest`, a major-only tag, or an `edge`/`main` tag.
- **Publishing is gated on `release_created`, not on a tag push.** A separate tag-triggered
  workflow would let anyone with push access publish an image by pushing a `v*` tag. Keeping
  `publish` in the run that created the release makes the merged release PR the only way in.
- **A failed `publish` is re-run, not re-released.** The tag and Release already exist; re-running
  the failed job builds the same commit and pushes the same tags. Releases are immutable, so a
  release with wrong *content* is fixed by the next patch release, never by moving its tag.
- **The image is checked on every pull request** by the `image` job in `tests.yml`, with the same
  smoke script the release uses (`.github/scripts/image-smoke.sh`). Keep the `Containerfile`
  `COPY`-only: a `RUN` step would need QEMU for `arm64` and `arm/v7`.

### The release App

release-please authenticates as a GitHub App, because pull requests and tags created with
`GITHUB_TOKEN` trigger no workflows — the release PR would never get its required checks. The
App's private key is the one long-lived credential in the repository, so everything around it is
arranged to limit who can read it and what it can do. These are security controls; do not
loosen them for convenience.

- **The key is readable only from `main`.** `RELEASE_APP_CLIENT_ID` and
  `RELEASE_APP_PRIVATE_KEY` are secrets of the `release` *environment*, whose deployment branch
  policy allows `main` only; the `release-please` job declares `environment: release`. The token
  action takes the App's Client ID (`client-id`), not its numeric App ID, which it deprecates. They are deliberately **not** repository
  secrets, which any workflow on any branch could read — write access alone would leak the key.
- **Least privilege twice over.** The App is private to `bond-os`, installed on this repository
  only, and holds Contents and Pull requests (read and write) and nothing else. The workflow also
  requests exactly those two permissions when minting each one-hour token, so a token stays
  narrow even if the App later gains more. Issues is deliberately absent; add it to both only if
  release-please demonstrably cannot label its PR without it.
- **No bypass on `main`.** The `main` ruleset requires a pull request and lists no bypass actors —
  not the App, not administrators. release-please never pushes to `main`; it pushes its own
  branch and opens a PR.
- **Release tags are write-once.** A tag ruleset on `refs/tags/v*` lets only the App create them
  and nobody update or delete them, and release immutability is enabled. Pinned versions —
  including `git clone --branch vX.Y.Z` in the Forgejo example — can never move under a consumer.
- **Outputs reach shell steps through `env:` only**, never `${{ }}` inside a `run:` body, and no
  workflow uses `pull_request_target`.

With all of the above, a stolen key can open junk PRs, push non-`main` branches and create a
*new* `v*` release — but cannot land code on `main`, alter an existing release or publish an
image. A forged release is visible on the releases page and missing from `CHANGELOG.md`.

**Key rotation:** yearly, and whenever someone who had access to the key leaves. An App can hold
two keys at once: generate the new key, replace `RELEASE_APP_PRIVATE_KEY` in the `release`
environment, confirm a release run succeeds, then delete the old key from the App. Delete the
downloaded `.pem` once it is stored.

**If the key leaks:** delete the key from the App settings immediately (tokens already minted
expire within the hour), generate a replacement as above, review the repository's recent
branches, pull requests and releases for anything the App did that a release run did not, and
delete any forged release and its tag (an administrator can, despite immutability).

### Repository settings (configured by hand)

- Merge buttons: rebase merging only; squash and merge commits disabled.
- Branch ruleset on `main`, **no bypass actors**: require a pull request (0 approvals — a sole
  maintainer cannot approve their own); allowed merge method rebase; required checks `test`,
  `image`, `commitlint`, branches up to date; block force pushes and deletion.
- Tag ruleset on `refs/tags/v*`: restrict creation (the release App is the only bypass actor),
  restrict updates and deletion (no bypass actors).
- Release immutability enabled.
- Environment `release`: deployment branches `main` only, no required reviewers, secrets
  `RELEASE_APP_CLIENT_ID` and `RELEASE_APP_PRIVATE_KEY`.
- The GHCR package `nexus-cleanup` is public and linked to this repository.

## Reference Nexus

Response shapes are taken from a local **Nexus 3.96 Community Edition** instance, which is the
source of every fixture under `tests/fixtures/`.

### What the reference instance hosts

48 repositories, of which **37 are proxies** across 9 formats:

| Format | Proxy repos | Components observed |
|---|---|---|
| yum | 16 | plentiful — several repos exceed one page |
| helm | 7 | 1 per repo |
| raw | 5 | 1–6 per repo |
| docker | 3 | 49 across all three |
| maven2 | 1 | **empty** |
| npm | 1 | 100+ |
| nuget | 1 | 100+ |
| pypi | 1 | 82 |
| conan | 1 | **empty** |
| huggingface | 1 | 9 |

An **apt proxy** (`apt-proxy-deb.debian.org`, Debian bookworm) and content for the empty conan
proxy were added specifically to back the `debian` comparator and the unorderable-group case;
see the two rows below.

| Format | Added for fixtures | Content |
|---|---|---|
| apt | `apt-proxy-deb.debian.org` | `hello` 2.10-2 / 2.10-3 / 2.10-5 × amd64 + arm64 = 6 components |
| conan | primed the existing proxy | `zlib` 1.3.1 / 1.2.13 / 1.2.12 |

### Which asset attributes 3.96 actually populates

Every asset carries `downloadUrl, path, id, repository, format, checksum, contentType,
lastModified, lastDownloaded, uploader, uploaderIp, fileSize, blobCreated, blobStoreName,
blobUpdated, blobRef, lastVerified, registryUrl` plus one format-specific map. Note that
`blobRef`, `blobUpdated`, `lastVerified` and `registryUrl` are **not in the published API
documentation** — first-hand evidence for why parsing must ignore unknown fields.

| Format | Attribute map | Carries an architecture? |
|---|---|---|
| docker | `{architecture, os, created, env, history, content_digest, …}` | **yes**, when the cached asset is a single-arch manifest |
| maven2 | `{extension, groupId, artifactId, version}` | no (classifier absent on this data) |
| npm | `{name, version}` | no |
| pypi | `{name, version, platform}` | `platform` present but `"UNKNOWN"` on observed data |
| nuget | `{is_latest_version, is_prerelease}` | no |
| helm | full chart metadata | no |
| raw | `{}` | no |
| huggingface | `{}` | no |
| apt | `{}` — **empty** | **yes, but in the component's `group` field** |
| yum | none | **yes, in the component's `group` field** (`noarch`, `x86_64`) |
| conan | `{}` | no |

**apt and yum both put the architecture in `group`, not in an attribute map.** A cached
`hello_2.10-2_amd64.deb` arrives as `name=hello, version=2.10-2, group=amd64` with
`asset.apt = {}`; an rpm arrives as `name=otopi-java, version=1.8.4-1.el7, group=noarch`.
Since `group` is already part of the retention key, these repositories split by architecture
correctly even before the variant adapter runs — but the adapter must read `group` so the
report *shows* the architecture rather than the implicit variant.

`group` means something different in every other format — the org for huggingface, the
directory for raw, the groupId for maven2 — so reading it as an architecture is an apt/yum
adapter rule, never a general one.

The variant sentinels are `*` (implicit: no architecture dimension) and `multiarch` (covers
every architecture: a docker manifest list or OCI index). `multiarch` is deliberately not
spelled `all`, because in Debian `all` is a real architecture value for arch-independent
packages.

**conan versions embed the recipe revision**: `1.3.1-_#cac0f6daea041b0ccf42934163defb20`. The
`generic` comparator cannot parse that, so conan groups are reported as skipped/unorderable —
correct strict behaviour, and a real corpus for that path.

Docker architecture coverage over the 49 observed components: `amd64` 23, `mips64` 2,
`arm64` 1, `arm` 1, absent 22. It is absent exactly when the cached asset is a manifest list
(`application/vnd.docker.distribution.manifest.list.v2+json`) or an OCI image index
(`application/vnd.oci.image.index.v1+json`) — a multi-architecture index legitimately has no
single architecture.

`raw` components have an **empty `version`** and carry the full path in `name`, so a raw
repository has no version dimension at all.

### Re-recording fixtures

```bash
nu tools/record-fixtures.nu --max-pages 1 apt-proxy-deb.debian.org conan-proxy-conan.io docker-proxy-hub yum-proxy-resources.ovirt.org yum-proxy-archives.fedoraproject.org npm-proxy-npm pypi-proxy nuget.org-proxy helm-jenkins raw-proxy-repo.almalinux.org proxy-hg
```

`NEXUS_URL`, `NEXUS_USERNAME` and `NEXUS_PASSWORD` must be set; keep them in a gitignored
`.nexus.env` (see `.nexus.env.example`) rather than in your shell history.

Recording is **idempotent**: two runs against an unchanged instance produce byte-identical
files, so `git diff` after a re-record shows exactly what Nexus changed and nothing else. That
property is what makes a Nexus upgrade a five-minute read rather than an investigation, and it
is worth preserving:

- **Identity fields** (`uploader`, `uploaderIp`, `blobStoreName`, `blobRef`) are replaced
  wholesale. `blobRef` matters as much as the rest — it embeds the blob store name and its
  UUID.
- **Volatile fields** (`size`, `lastDownloaded`, `lastVerified`) are normalised to a constant.
  The tool never reads them and they change on their own, so recording them verbatim would
  bury every real change in churn. `lastModified`, `blobCreated` and `blobUpdated` are left
  alone — they are stable per artifact.

If a re-record produces a large diff, read it before committing: a changed response *shape* is
a signal to revisit the variant adapters, not something to accept silently. After any
re-record, `nu tests/run-tests.nu` must still pass — `tests/test-fixtures-clean.nu` is the
guard that nothing from the instance leaked in.

Use `--max-pages 1` unless you specifically need paging fixtures: docker components carry the
image's full build history and pages get large fast.

### Never write or print an `http --full` response wholesale

`http get --full` returns `headers.request`, which contains the `Authorization: Basic …`
header — the credentials in recoverable form. Read `.body` and `.status`; never log, save or
echo the whole response record. The recorder writes response bodies only, and
`tests/test-fixture-redaction.nu` guards it.

## Deliberate exceptions and standing decisions

### No Python, no `uv`

The global Python/`uv` convention does not apply here: the tool contains no Python. If the tool,
its tests or its dev tools ever need a helper, write it in Nushell rather than reaching for
another runtime — the image has nothing else in it.

This applies to the tool side of the boundary in [Runtime](#runtime). Maintenance automation is
free to use an established third-party tool; if one of those is ever Python-based, the global
`uv` convention applies to it again (dependencies in `pyproject.toml`, `uv.lock` committed,
`uv sync --locked` in CI).

### Dry run is the default; `--execute` opts in

There is deliberately **no `--dry-run` flag**. The safe mode is the one you get by forgetting a
flag, because the failure mode of this tool is mass deletion. Do not invert this polarity, and
do not let any other flag or environment variable imply `--execute`.

The deletion cap, the refusal of non-proxy repositories, and strict version ordering are the
other three layers of the same guard. Treat them as a set.

### No Nexus version gating

Nothing reads the Nexus version or branches on it. Support for older instances comes from
tolerant parsing: unknown fields ignored, every documented field treated as possibly absent,
and the variant layer falling back from format attribute to filename to implicit variant.

Concretely: send no page-size parameter (since Nexus 3.74.0 the Components API fixes it at 100
and honours none) and page purely on the continuation token. Version-detection code rots — a
branch written for 3.96 keeps firing on 4.x.

### No Community Edition quota awareness

Community Edition currently caps a deployment at 40,000 components and 100,000 requests per
day and blocks new uploads above them, which makes this tool one way back under the ceiling.
The tool models none of it: no usage endpoint, no headroom reporting, no self-throttling.

Those numbers are Sonatype policy rather than API behaviour and have already moved once (they
were 100,000 and 200,000 before 3.87.0). Baking them in dates the tool and makes it wrong on
Pro, where neither limit exists. The report already carries the component counts an operator
needs to answer the headroom question.

### Docker variants come from the asset attribute, and an index means "all"

Nexus 3.96 populates `assets[].docker.architecture` directly on the Components API — an
earlier assumption that it was reachable only through the Registry v2 API was wrong, and was
corrected against the reference instance.

Three cases: a single-architecture manifest yields that architecture; a manifest list or OCI
image index yields the **all-architectures** variant; anything else yields the implicit
variant. Keep the all-architectures variant distinct from the implicit one — collapsing them
would make "covers every architecture" look identical to "this format has no architecture
dimension".

### Scope is part of the retention key, and its rule is per-format

A repository can hold the same package name and architecture for several distribution
releases or repository sections, and **nothing in the component metadata says so** — only the
asset path does. The retention key is therefore
`(repository, scope, group, name, variant)`.

- **yum** → the asset's directory. Separates `/releases/44/…` from `/updates/44/…` and one
  EPEL version from another, with no heuristic and no architecture-name list to maintain.
- **apt** → the repository's configured `apt.distribution`.
- **everything else** → one implicit scope.
- `--scope-from-path <regex>` overrides the rule everywhere.

**Do not apply directory scoping to every format.** A maven-style layout puts the version in
the directory, so directory scope would give every version its own group and silently retain
everything — cleanup that appears to run and deletes nothing.

Measured on `fedora-current-proxy` (12,423 components): directory scoping still frees 5,117
components at `--keep 1` versus 6,552 unscoped, while protecting 1,435 that would otherwise be
deleted across the releases/updates boundary.

### Do not try to read apt `dists` metadata

It has been tried and it does not work here. Nushell has **no decompression command of any
kind**, and Debian serves `Packages` only as `.gz`/`.xz` — the uncompressed form 404s both
upstream and through Nexus. The uncompressed `Release` file lists only the suite name,
architectures and index checksums, never package-to-version mappings. Parsing indexes would
mean shelling out to `gzip`/`xz`, which the no-external-binaries rule forbids.

It is also nearly unnecessary: `apt.distribution` pins a proxy to one suite and clients only
learn pool paths from that suite's index. The residual risk is that `enforceDistribution`
defaults to false, so a client that requests another suite's pool path directly can leave
foreign-suite files in the cache that the tool cannot distinguish. Documented in `README.md`;
mitigated by the dry-run default, `--keep` and the deletion cap.

### The keep count is checked before the ordering

A group with `N` or fewer components is retained without being ordered at all. Do not reorder
these checks: `raw` components carry an empty `version`, so ordering first would report every
one of them as "skipped: unorderable" while deleting nothing, drowning the groups that matter.

### `--from-path`: unmatched components are decided before grouping

With a path pattern, a component the pattern does not match is emitted as `keep` /
`outside-pattern` *before* grouping, in `policy plan`. It never enters a group, so no keep count,
ordering outcome or multi-variant rule can reach it. This is the guarantee operators rely on —
"the version directories must not be touched" — so keep it structural. Do not move it into a
condition inside the decision logic, and do not let unmatched components fall back to their
metadata key: an operator who wrote a pattern expects it to be the whole rule.

### Distinct-version ranking applies only to path-derived groups

In a path-derived group the unit of retention is a distinct version: a directory is one item
however many files it holds, and many files sharing one version is expected. In an ordinary group
two components with the same version still mean `group-ambiguous`. Do not relax that globally —
there, a shared version signals something the tool does not understand. Two *distinct* version
strings comparing equal (`1.0` / `1.0.0`) are ambiguous in both kinds of group.

### `date` is never chosen by default

`version scheme-for-format` never returns `date`, for any format including `raw`. Eight-digit
directory names are too easy to mistake for dates; selection must be explicit
(`--version-scheme date`). Calendar validation uses `into datetime --format "%Y%m%d"` — no
external binary — and an impossible date makes its group unorderable rather than guessed.

### Report fields are only ever appended

CSV consumers address columns by position. A new record field goes at the end of `FIELDS`,
never in the middle. `path` was appended for this reason.

### Strict version ordering never falls back

A group whose versions cannot all be parsed by the selected comparator, or in which two
distinct components compare equal, is skipped whole and reported. Do not add a timestamp,
API-order or lexicographic fallback: a confident wrong ordering deletes the wrong artifact,
which is the one outcome the design exists to prevent.

## Planning

Planning artifacts live in `openspec/`. Behaviour changes go through OpenSpec — revise the
specs before the code, not after.
