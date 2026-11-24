# Design

## Context

See `proposal.md` for the problem. `upgrade-candidates` discovers fixed `init` outputs and
`configs/*.yaml|yml`, after which `upgrade` reads every candidate and writes changed content with
`save --force`. `stale-pins` reuses candidate discovery from `init` to inspect the same files. A
symlink accepted at discovery can therefore redirect either a read or a write outside the target
repository.

## Goals / Non-Goals

**Goals:**

- Establish one no-symlink rule for upgrade candidate paths and their parent directories.
- Apply the rule before any candidate content is read or written.
- Keep normal upgrade, `--check` and stale-pin inspection consistent.

**Non-Goals:**

- Replacing or unlinking symlinks.
- Protecting arbitrary files that are not upgrade candidates.
- Adding a platform-specific atomic filesystem primitive.

## Decisions

### Validate candidate paths before content inspection

Candidate discovery will return the current relative paths but perform a path-type walk before
content is opened. A symlink at the target candidate or at any parent below the requested
repository is unsafe. Validation runs across the complete candidate set before `upgrade` computes
any transformed content, so the command remains all-or-nothing.

Refusing the path is preferred to unlinking and replacing it because it leaves ambiguous operator
state untouched and avoids a destructive recovery policy.

### Share the candidate walk with stale-pin inspection

`stale-pins` is advisory, so it should not convert an unsafe path into a stale-pin warning or read
an external target. It will skip unsafe candidates while `upgrade` and `upgrade --check` raise a
usage error for the same condition. This differs in outward action but reuses one path-safety
decision.

### Treat the target directory itself as trusted input

The operator may intentionally pass a symlink as the upgrade directory. The boundary begins at
that resolved target; only symlinks at candidate paths or in directories below it are rejected.
This preserves the documented ability to name a directory while preventing paths inside the
repository from redirecting candidate access.

## Risks / Trade-offs

- [A configuration uses symlinks deliberately] → `upgrade` now refuses that repository. The
  operator must replace the candidate symlink with a regular file before moving version pins.
- [A path changes after validation] → Like the existing filesystem operations, Nushell does not
  provide an atomic open-by-directory-handle primitive. The validation closes the ordinary
  redirection case without adding external runtime dependencies.

## Migration Plan

No migration is required. Existing repositories with regular candidate files keep their current
behavior. Rollback is the previous release; no file format changes.
