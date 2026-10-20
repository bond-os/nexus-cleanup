## Why

Build pipelines publish their output to **raw hosted** repositories as dated directories —
`app/20261019/…`, `app/20261019-hotfix/…` — and nothing ever removes the old ones. Path-derived
retention (`--from-path` with the `date` scheme) already expresses the retention operators want
for exactly this layout, but the tool refuses every non-proxy repository, so it can only be
applied to proxies.

Hosted content differs from a proxy cache in one way that matters: it is the only copy. A wrong
deletion in a proxy costs a re-download; in a hosted repository it is permanent. The change
therefore opens hosted repositories as narrowly as the use case allows instead of lifting the
proxy-only rule.

## What Changes

- **Raw hosted repositories become eligible**, and only those. A hosted repository of any other
  format is still refused, with a message stating that only raw is supported. Group repositories
  stay refused.
- **Opt-in by flag and by name.** A new `--allow-hosted` switch is required, and a hosted
  repository is selected only by naming it. `--pattern` never matches a hosted repository,
  whether or not the switch is given, so a glob cannot sweep one in. Naming a hosted repository
  without the switch is refused with a message naming the switch.
- **The opt-in is also a configuration file key**, `allow-hosted`, because choosing which
  repositories to touch is part of a reviewed configuration. Unlike `execute`, it deletes
  nothing on its own: a run with it is still a dry run unless `--execute` is passed.
- **No pattern, nothing to delete — and the tool says so.** A raw hosted repository processed
  without `--from-path` has every component in a group of one, so nothing is deleted. The tool
  states this on stderr per repository rather than refusing, so a dry run over it remains a
  harmless inventory.
- **Partial deletion of a build directory is reported, not prevented.** A directory is deleted
  file by file; if some deletions fail, the remaining files stay and appear in the report with
  their error, and the run exits 1, as for any deletion failure today.
- **Repository configuration is read from the endpoint matching the repository's type** rather
  than a hardcoded proxy path.
- **BREAKING (wording only)**: the requirement "Repository discovery restricted to proxy
  repositories" is renamed and rewritten; behaviour for every run that does not pass
  `--allow-hosted` is unchanged.

Non-goals: hosted repositories of other formats (docker, maven, npm, …) — each needs its own
fixtures and format-specific analysis first; selecting hosted repositories by pattern; a
transactional "whole directory or nothing" deletion; renaming the project or repository.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities
- `nexus-cleanup/nexus-api-client`: repository eligibility widens from proxies to proxies plus
  raw hosted repositories under an opt-in; format configuration is read from the endpoint for
  the repository's type.
- `nexus-cleanup/cli`: repository targeting distinguishes names from patterns for hosted
  repositories; a new opt-in switch; a diagnostic for raw hosted repositories processed without
  a path pattern.
- `nexus-cleanup/config-file`: `allow-hosted` joins the recognised keys. This capability is
  introduced by `add-config-file`, which must be applied and archived first.

## Impact

- **Code**: `api.nu` (`select-proxies` is renamed `select-repositories` and understands the
  opt-in; no alias is kept for module importers; the
  repository-config URL uses the type), `config.nu` (`allow_hosted`, the file key), the
  entrypoint (`--allow-hosted`), `run.nu` (passing the opt-in, the per-repository diagnostic,
  enumeration notes naming the type).
- **Tests**: extensions to `test-api.nu`, `test-config.nu`, `test-config-file.nu`, `test-cli.nu`,
  `test-run.nu` and `test-end-to-end.nu`; a recorded raw hosted fixture from the reference
  instance (`raw-iso` or `packer-bases`).
- **Safety model**: the "refusal of non-proxy repositories" layer becomes "refusal of every
  repository that is neither a proxy nor an explicitly named, explicitly allowed raw hosted
  repository". The other three layers are unchanged.
- **Docs**: `README.md` (eligibility, the switch, the hosted raw worked example, the
  partial-deletion behaviour), `AGENTS.md` (project description, the safety layer, a standing
  decision on why hosted support is raw-only and name-only), the `nexus-api-client` and
  `retention-policy` spec purposes, which say "proxy" and "cached".
- **Depends on**: `add-config-file`.
