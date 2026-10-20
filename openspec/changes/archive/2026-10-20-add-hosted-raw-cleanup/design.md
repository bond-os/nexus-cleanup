## Context

See `proposal.md` for motivation and `specs/` for the contract. The code this change touches:

- `api select-proxies` takes the repository listing, the named repositories and a pattern. A
  named non-proxy raises; a pattern filters to `type == "proxy"`. Its error is raised inside
  `cleanup run`, so the entrypoint maps it to exit code 3, as for every refusal that needs the
  repository listing to decide.
- `api repository-config` builds `/service/rest/v1/repositories/<format>/proxy/<name>`. Only
  formats in `SCOPE_CONFIG_FORMATS` (apt) reach the request, so raw never calls it — the
  hardcoded `proxy` is latent, not live.
- raw components have the same shape whatever the repository type: `name` is the full file
  path, `group` the directory, `version` empty, one asset each. Without `--from-path` every raw
  component is its own group of one and is kept by the keep-count pre-check.
- The reference instance already has two raw hosted repositories, `raw-iso` and
  `packer-bases`, so a recorded hosted fixture needs no new repository.

This change depends on `add-config-file`: it adds `allow-hosted` to the key table that change
introduces, and its config-file delta can only be archived after that change's is.

## Goals / Non-Goals

**Goals:**

- Make the motivating case — dated build directories in a raw hosted repository — runnable with
  the exact `--from-path` / `date` configuration already used on raw proxies.
- Keep every run that does not pass the opt-in byte-for-byte as it is today.

**Non-Goals:**

- Any hosted format other than raw, and any group repository.
- Making a directory's deletion atomic.
- A report field for the repository type.

## Decisions

### Raw only, because raw has no format-side coupling

A raw component is a file and nothing else refers to it. Every other hosted format has something
that does: a docker manifest list refers to per-platform manifests stored as their own
components, maven metadata and SNAPSHOT timestamps are rebuilt around the files, npm dist-tags
point at versions, yum repodata is regenerated from what remains. Deleting correctly in each
means studying that format's hosted layout against recorded fixtures first. Raw needs none of
it, and the retention rules raw needs exist already.

*Alternative considered:* a general hosted opt-in with per-format warnings. Rejected: a warning
is not a guard, and the first unexamined format would delete with the confidence of a tested
one.

### Hosted repositories are selected by name only

A pattern's reach changes whenever someone creates a repository. With hosted repositories in a
pattern's reach, a scheduled run over `raw-*` would silently start pruning a hosted repository
created next year. Naming forces the repository into a reviewed list. The pattern therefore
keeps filtering to `type == "proxy"`, whether or not the switch is given, and a matching hosted
repository is noted as excluded with a hint to name it.

### The opt-in is a switch, separate from execute, and may live in the file

`--allow-hosted` widens what can be *selected*; `--execute` decides whether anything is
*deleted*. Keeping them separate keeps the dry-run guarantee whole: a run with the switch is
still a dry run without `--execute`. Because selection is exactly what a configuration file is
for, `allow-hosted` is a file key, unlike `execute`.

### The selection command is renamed, not wrapped

`api select-proxies` becomes `api select-repositories <listing> <names> --pattern <glob>
--allow-hosted`, which implements the eligibility rules in one place and raises every refusal
message. The old name is removed rather than kept as a wrapper: it would describe the wrong rule,
and this change does not preserve the module's command names for external importers.

### Repository configuration follows the repository's type

`api repository-config` builds its URL from the repository's own `type` instead of the literal
`proxy`. No raw run issues the request, but the next format that needs configuration would
otherwise fail silently — a failed configuration read is deliberately non-fatal and yields no
declared value.

### No path pattern: proceed and say so

Without `--from-path` a raw hosted repository deletes nothing. Refusing the run would turn a
harmless inventory into an error; staying silent would let an operator believe a scheduled
cleanup is working. A per-repository stderr diagnostic is the middle path, and it leaves the
report and exit code alone so that a dry-run inventory stays a green job.

### Partial deletion is reported, not prevented

A directory is several components deleted one request at a time. Nexus offers no transaction
across components, so all-or-nothing would mean pre-checks that can still race. When some
deletions fail, the files that remain carry their error in the report and the run exits 1. The
directory was due for deletion anyway; the report names exactly what is left, and the next run
retries it.

### No mandatory deletion cap for hosted runs

A hosted deletion already takes four explicit acts: the switch, the repository's name, a path
pattern, and `--execute`. The existing cap remains available and the README's hosted example sets
it.

*Alternative considered:* refusing an executing hosted run without `--max-deletions`. Rejected
for now: a mandatory number is usually set high to make the error go away, which guards nothing
while looking like a guard. Revisit if a hosted run ever deletes more than its operator expected.

## Risks / Trade-offs

- [A consumer still references an old build by URL] → Inherent in pruning; the keep count is the
  operator's choice. The README's hosted section leads with a dry run and the report's per-path
  records, which show exactly which URLs will stop working.
- [A backfilled directory with an old date is deleted on the next run] → Inherent in date
  ordering; documented beside the worked example.
- [A file in a directory being uploaded during the run] → The directory being written is the
  newest and is within the keep window; enumeration is a snapshot, so a file uploaded after it is
  never a deletion candidate in that run.
- [`allow-hosted: true` added to a file by anyone who can edit the configuration repository] →
  It cannot cause a deletion without `--execute`, which stays in the pipeline definition, and the
  repository must also be named in the same reviewed file.
- [The recorded hosted repositories do not have a dated layout] → The recorded fixture proves
  that hosted raw components have the proxy shape; the dated layout is tested with the existing
  synthetic fixture served from a stubbed listing that declares the repository hosted.

## Migration Plan

Additive. Runs without the switch are unchanged. Rollback is pinning the previous image tag.
