## Context

Greenfield repository; nothing exists yet beyond the OpenSpec scaffold. See `proposal.md`
("Why") for motivation and `specs/nexus-cleanup/**` for the behaviour contract.

Constraints that shape the approach:

- **Runtime is Nushell in a container.** No Python, no `curl`, no `jq`. Nushell 0.115 already
  provides everything needed: `http get/delete` with `--user/--password`, `--max-time`,
  `--full` and `--allow-errors`; `sort-by --custom` with a two-argument comparator closure;
  `to json` / `to csv`; `std assert`.
- **Nushell breaks compatibility between minor releases.** A version floor must be pinned and
  exercised in CI against the exact container tag.
- **Deletion is one-way for the cache.** Proxy contents are re-fetchable from upstream, which
  is what makes this safe in principle, but an upstream that yanks a version will not serve it
  again. Every default is chosen so that a mistake produces a report, not a deletion.
- **Nexus API shape varies by version and format.** The generic Components API is stable; the
  per-format attribute maps on assets are not uniformly present across Nexus releases or
  formats. The variant layer must degrade rather than guess.
- **A live reference instance is available.** A local Nexus 3.96 Community Edition instance is
  the ground truth for every response shape the tool parses, and the source of the committed
  test fixtures.

## Goals / Non-Goals

**Goals:**

- Pure decision logic that is testable with no Nexus reachable — the whole plan is a function
  from a component list to a decision list.
- A single injection point for HTTP so tests substitute fixtures for the network.
- Ordering that is correct per ecosystem, and that refuses rather than guesses.
- A report that is both the machine contract and the source for the human render.

**Non-Goals:**

- Rendering the human report itself. This change produces the data; rendering is a downstream
  step (or a follow-up change).
- Reading Docker manifest lists to split a tag by architecture (see Decisions).
- Concurrency. Deletions run sequentially; a parallel mode is a later change if throughput
  becomes a problem.
- Blob store compaction. Deleting components frees space only after Nexus' own
  "Compact blob store" task runs; that stays an operator concern.

## Decisions

### Enumerate with the Components API, not the Search API

`GET /service/rest/v1/components?repository=<name>` with `continuationToken` paging is the
authority on what a repository actually holds. The Search API is richer — it exposes
per-format attributes and can sort server-side — but it is backed by an index that can lag or
drift from the blob store. Building a deletion plan on a stale index risks deleting the wrong
thing, and the failure mode is silent. Enumeration therefore uses Components; the Search API
is used at most as an optional enrichment source for variant derivation, never as the source
of truth for what exists.

*Alternative considered:* Search API only, for its sort and attribute support. Rejected on the
staleness risk.

### HTTP behind an injectable client record

Every Nexus call goes through a small client value holding the base URL, credentials, timeout,
retry policy and a `fetch` closure. Production builds the closure over `http get` / `http
delete`; tests build it over a fixture table. This keeps the retry/pagination logic under test
without a network and without mocking Nushell built-ins.

*Alternative considered:* calling `http get` directly from the enumeration commands and
testing only against a live Nexus. Rejected — it makes the pagination and retry rules, which
are exactly the risky parts, untestable in CI.

### `--execute` opts in; there is no `--dry-run`

The safe mode is the mode you get by forgetting a flag. A `--dry-run` flag that must be
remembered is the wrong polarity for a job whose failure mode is mass deletion. The report's
`mode` field, the deletion cap, and the refusal of non-proxy repositories are the other three
layers of the same guard.

### Three version comparators, selected by repository format

- `generic` — dotted numeric core with optional semver pre-release and ignored build metadata.
  Default for formats with no ecosystem-specific rule (npm, pypi, nuget, raw, maven release
  versions).
- `debian` — dpkg semantics: `epoch:upstream-revision`, alternating digit/non-digit segments,
  `~` sorting before the empty string. Used for apt repositories.
- `rpm` — `rpmvercmp` semantics over `epoch:version-release`. Used for yum repositories.

Selection is by repository format with a `--version-scheme` override. Implementing deb and rpm
ordering is deliberate scope: without them, apt and yum proxies — the ones that grow fastest —
would be permanently skipped as unorderable, which would defeat the tool.

*Alternative considered:* a single "natural sort" for everything. Rejected: natural sort ranks
`1.0-rc1` above `1.0` and mishandles deb epochs and `~`, so it produces confident wrong
deletions — the one outcome the strict mode exists to prevent.

### The keep count is checked before the ordering

A group holding `N` or fewer components has nothing to delete regardless of how its versions
would sort, so the keep count is evaluated first and such a group is retained without ever
being ordered.

This is not a shortcut, it is what makes the report readable. The reference instance's `raw`
proxies carry an **empty `version`** on every component, with the full path in `name` — no
version dimension at all. Checking orderability first would report every raw component as
"skipped: unorderable" while deleting exactly nothing, burying the groups an operator actually
needs to look at. Deletions are identical either way.

### Strictness is a property of the group, not of a pair

A group is orderable only when *every* version in it parses under the selected comparator and
no two distinct components compare equal. Any violation skips the whole group. This makes
strictness decidable and local: the operator sees "this group was skipped, because of this
version string", not a partially-applied ordering. Docker tag sets like
`{1.2.3, 1.3, latest}` are exactly the case this protects.

### Scope is a fourth dimension of the retention key

A repository can hold the same component name and architecture for more than one distribution
release or repository section, and nothing in the component metadata says so. The retention
key therefore carries a `scope` derived per format:

- **yum** → the asset's directory. Release trees, updates trees and EPEL versions all live in
  distinct directories, so this separates them without a heuristic and without a list of
  architecture names to maintain.
- **apt** → the repository's configured `apt.distribution`. A Nexus apt proxy is configured for
  a single suite, so the scope is constant per repository; it is carried anyway so the report
  states which suite a repository represents.
- **everything else** → one implicit scope, behaving exactly as though the dimension did not
  exist.
- `--scope-from-path <regex>` overrides the rule for every targeted repository.

Evidence from the reference instance's `fedora-current-proxy` (12,423 components, remote
`dl.fedoraproject.org/pub/fedora/linux/`, holding both `/releases/44/` and `/updates/44/`):

| Key | Groups | Groups with >1 version | Deletable at `--keep 1` |
|---|---|---|---|
| no scope | 5,871 | 2,222 | 6,552 |
| directory scope | 7,306 | 1,641 | 5,117 |

Scoping protects 1,435 components that would otherwise be deleted across the
releases/updates boundary, and still frees 41% of the repository. Without it,
`kcm-plasmalogin-6.6.4-1.fc44` in the frozen GA tree is deleted because the updates tree
carries 6.7.4 — a different artifact serving a different purpose.

*Why not directory scope for every format:* a maven-style layout puts the version in the
directory (`…/widget/1.2.3/widget-1.2.3.jar`), so scoping by directory would give every version
its own group and silently retain everything. Scope rules must be per-format for that reason
alone.

### Reading apt `dists` metadata was rejected as unimplementable

The obvious way to give apt a true per-suite scope is to parse each suite's `Packages` index
and map pool files back to suites. It cannot be done here: Nushell has no decompression
command of any kind, and Debian serves `Packages` only as `.gz`/`.xz` — the uncompressed form
is a 404 both upstream and through Nexus. The uncompressed `Release` file carries only the
suite name, architectures and index checksums, not package-to-version mappings. Recovering the
suite would require shelling out to `gzip`/`xz`, which the CLI spec forbids.

It is also close to unnecessary. `apt.distribution` on the repository config pins a proxy to
one suite, and clients only learn pool paths from that suite's index, so a proxy holds one
suite's pool files in normal use.

*Residual risk to accept:* `enforceDistribution` defaults to false, so Nexus does not block a
client that requests another suite's pool path directly. A repository that has accumulated
foreign-suite pool files that way holds versions the tool cannot tell apart. The dry-run
default, `--keep` and the deletion cap are the mitigations; documented in `README.md`.

### Variant derivation is a per-format adapter with an honest fallback

Adapter order per format: documented asset attribute → filename/path parse → implicit variant.
The implicit variant is reported as such, so "no architecture split was applied here" is
visible in the report rather than being indistinguishable from "this component is
architecture-independent".

**Docker does expose an architecture, and it is used.** This reverses an earlier assumption in
this design, which held that architecture was reachable only through the Docker Registry v2
API. Probing the reference 3.96 instance showed otherwise: `assets[].docker.architecture` is
populated directly on the Components API. Across 49 observed components — `amd64` 23,
`mips64` 2, `arm64` 1, `arm` 1, absent 22 — the attribute is present exactly when the cached
asset is a single-architecture image manifest, and absent exactly when it is a manifest list
(`application/vnd.docker.distribution.manifest.list.v2+json`) or an OCI image index
(`application/vnd.oci.image.index.v1+json`).

So Docker gets three cases, and the third is what makes it honest:

- single-architecture manifest → that architecture is the variant;
- manifest list or OCI index → the **all-architectures variant**, because such a component
  genuinely covers every architecture rather than having none;
- anything else → the implicit variant.

The all-architectures variant is distinct from the implicit one on purpose. Collapsing them
would make "this component covers every architecture" indistinguishable from "this format has
no architecture dimension", and those call for different operator judgement.

*Consequence to accept:* an image whose tags are cached as a mix of indexes and single-arch
manifests splits into two groups, and each keeps its own newest. That under-deletes, which is
the safe direction, and no image in the observed data does it.

### Report is a Nushell table first, an encoding second

Planning returns structured Nushell data; JSON and CSV are two encodings of the same table
produced at the last step. That makes the module usable programmatically (per the CLI spec's
module requirement) and keeps the two encodings from drifting, since neither is the primary
representation.

CSV carries the records only; the aggregate goes to `--summary-out` as JSON, because inventing
a summary row inside the table would corrupt it for every ordinary CSV consumer.

### Capability probing, not version gating

Nothing in the tool asks Nexus what version it is or branches on the answer. Instead: unknown
fields are ignored, every documented-but-optional field is treated as possibly absent, and the
variant layer falls back from attribute to filename to implicit variant. The worked example is
paging — since 3.74.0 the Components API returns a fixed 100 items per page and honours no
page-size parameter, so the client sends none and pages purely on the continuation token,
which is correct on every version either way.

*Alternative considered:* detecting the version (from the `Server` header or the system
information endpoint) and selecting behaviour per version. Rejected: it adds a version matrix
to test and a detection path that fails on instances where the system information endpoint is
restricted, and it buys nothing that tolerant parsing does not already give. Version detection
is also the kind of code that quietly rots — a branch written for 3.96 keeps firing on 4.x.

*Consequence:* an older instance that exposes fewer attributes degrades to filename parsing or
to the implicit variant, and the report shows which happened. It does not error and it does not
silently guess.

### Fixtures recorded from the live 3.96 instance, by a committed recorder

`tools/record-fixtures.nu` hits a live Nexus, walks the Repositories and Components APIs, and
writes redacted responses to `tests/fixtures/<format>/`. Redaction is part of the tool, not a
manual step: base URL and host, credentials, `uploader`, `uploaderIp`, the host portion of
`downloadUrl`, and blob store names are replaced with stable placeholders before anything is
written. A test asserts that no committed fixture contains a hostname, credential or uploader
identity, so a careless re-record cannot leak the instance into the repository.

Recording is reproducible rather than a one-off: when Nexus changes a response shape, the fix
is to re-run the recorder against an upgraded instance and read the diff.

*Alternative considered:* generating fixtures in CI against a throwaway Nexus container.
Rejected — it makes the test suite need a live Nexus, which is exactly the property this
change is buying.

### Every fixture is real; missing proxy repositories are created first

Rather than hand-writing fixtures for formats the reference instance does not host, a proxy
repository is stood up locally for each Community Edition format worth supporting and primed
with several versions before recording. Hand-written fixtures encode what the documentation
says, and the documentation is exactly what has proven unreliable about per-format attribute
maps — a synthetic fixture would let the variant adapters pass their tests while failing on
the real payload.

*Cost accepted:* more setup on the reference instance, and the primed components count against
that instance's own component total.

### Deliberately edition-agnostic

Community Edition currently caps a deployment at 40,000 components and 100,000 requests per
day, blocking new component uploads above those thresholds — which makes this tool one way back
under the ceiling. The tool nonetheless models none of it: it does not read the usage endpoint,
does not report headroom against a ceiling, and does not throttle itself against a request
budget.

Rationale: those numbers are Sonatype's policy, not API behaviour, and they have already moved
once (they were 100,000 and 200,000 before 3.87.0). Baking them in dates the tool and makes it
wrong on Pro instances, where neither limit exists. The report already carries the component
counts an operator needs to answer the headroom question themselves.

*This is a conscious exclusion.* Do not add CE quota awareness without a new decision here.

### Module layout

```
nexus-cleanup.nu          # entrypoint: flags -> module calls -> exit code, nothing else
nexus-cleanup/
  mod.nu                  # public surface re-exported
  config.nu               # env + flag resolution, validation
  api.nu                  # client record, retry, pagination, repo/component/delete
  variants.nu             # per-format variant adapters
  versions.nu             # generic / debian / rpm comparators
  policy.nu               # grouping, ordering, keep/delete/skip decisions
  report.nu               # record schema, aggregate, json/csv encoding
tools/
  record-fixtures.nu      # live Nexus -> redacted fixtures; not used at runtime
tests/
  fixtures/<format>/      # recorded, redacted Nexus responses per format
  *.nu                    # std assert tests, runner script
```

`tools/` is development-time only: the shipped module never reads it, and the container image
does not need it.

### Testing without a Nexus

Pure layers (`versions`, `variants`, `policy`, `report`) are tested directly on the recorded
fixtures — these carry the deletion risk and get the heaviest coverage, including the deb/rpm
comparator cases from those ecosystems' own test corpora. `api` is tested through the injected
`fetch` closure, replaying recorded pages for pagination and synthesising status codes for
retry classification and error mapping. A separate, non-CI smoke script runs a dry run against
the reference instance to confirm the fixtures still describe reality.

## Risks / Trade-offs

- **A comparator bug deletes the wrong version.** → Strict group ordering, dry-run default,
  deletion cap, and comparator test corpora taken from dpkg and rpm test data. The comparators
  are the highest-value tests in the repository.
- **Nexus does not expose the architecture attribute the adapter expects, so everything
  collapses to the implicit variant and one architecture's only build is deleted.** → Largely
  retired by recording real fixtures for every supported format from the reference instance, so
  the adapters are written against observed payloads rather than documentation. What remains is
  the older-instance case, covered by the filename fallback; the implicit variant is explicit in
  the report, the recommended first run is a dry run reviewed by a human, and `--fail-on-skip`
  plus the deletion cap give CI a tripwire.
- **An image cached as a mix of multi-architecture indexes and single-architecture manifests
  splits into two groups**, so an obsolete tag survives because it sits alone in its group. →
  Under-deletion rather than data loss, and visible in the report because the variant column
  distinguishes the two. Revisit only if operators report it as noise.
- **Fixtures drift from a Nexus that has since been upgraded**, so the suite passes against a
  shape the live server no longer returns. → The recorder makes re-recording cheap, and the
  end-to-end dry run against a real instance (task group 10) is the periodic check that fixtures
  still match reality.
- **Nushell minor release breaks the script in the CI image.** → Pin the container tag, declare
  a version floor in `AGENTS.md`, and run the test suite in that image in CI.
- **Deleting components frees no disk until blob compaction runs**, so an operator may conclude
  the tool did nothing. → State it in `README.md` and in the human-report guidance.
- **Long enumerations on large proxies** (tens of thousands of components) are sequential and
  may be slow. → Acceptable for a scheduled job; parallelism is a later change with a measured
  need behind it.
- **An upstream that yanks a version makes a cached deletion permanent.** → Documented; `--keep`
  above 1 is the mitigation for repositories where this matters.

## Migration Plan

Not applicable — new repository, no existing behaviour or data to migrate. Rollout is
operational: land the tool, run it dry against production proxies, review the report, then
enable execution for one repository with a conservative cap before widening the pattern.

## Open Questions

- Whether the human-readable renderer should live in this repository or in the consuming
  pipeline. Deferrable: the report contract is fixed either way.
