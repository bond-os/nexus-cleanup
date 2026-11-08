# Design

## Context

See proposal.md for the motivation and specs/ for the behaviour. `scaffold plan` renders the
selected templates into `[{path, content}]`, and `scaffold write` checks every path before writing
and either refuses or, with `--force`, overwrites. `scaffold upgrade` already knows every pin `init`
writes. `init` and `upgrade` parse their own arguments, and every failure of either exits 2.

## Goals / Non-Goals

**Goals:**

- Add files to an existing repository without touching what is there.
- Refresh a chosen part of a repository without overwriting the pipeline.
- Show what a command would do before it does it.

**Non-Goals:**

- A new subcommand. `extend` was considered: its main benefit would be inferring `--ci`, and both
  Jenkins variants write `Jenkinsfile`, so inference cannot work for them.
- A line-by-line diff, merging into existing files, or three-way comparison against the release
  that wrote a file. The last would need the old template, which the tool does not have offline.
- Moving template directories. `templates/common/` keeps its layout, because a template stays
  stored at the path it is written to below its area, and the groups only name what already exists.

## Decisions

### `--only` filters the selection

`--only` narrows the files the selection flags chose; it does not replace them. The alternative was
one flag per group with `--ci` optional, which is shorter to type (`init --editor intellij`). But a
fresh `init --ci gitlab` must still write the base files, so that model needs implied groups, and
"the flags given are what gets written" stops being true. With a filter, each existing flag keeps
its one meaning and only one flag is new.

### Groups follow what is safe to overwrite

| Group | Files | Edited by the operator? |
|---|---|---|
| `pipeline` | the selected CI system's file | yes: URL, schedule |
| `runner` | `ci/run-configs.sh` | no |
| `base` | `.editorconfig`, `.gitattributes` | no: content fixed by the spec |
| `example` | `configs/example.yaml` | no, now that it is copied rather than edited |
| `editor` | the files of each `--editor` | rarely |
| `env` | the files of each `--env` | `.gitignore` often |

`run-configs.sh` is separate from the pipeline even though the pipeline calls it. In one group,
refreshing the script would overwrite the operator's URL. `scaffold plan` adds a `group` field to
each record, derived from a table beside `COMMON`, and filters on it. The renderer and the tests that
read `path` and `content` are unaffected.

A group that the selection leaves empty (`--only editor` with no `--editor`) is a usage error,
because the run would otherwise write nothing and exit 0.

### One decision per file, used for writing and for checking

Each planned file gets a state (`new`, `identical`, `differs`) and, from the mode, an action
(`write`, `skip`, `overwrite`, `refuse`). `scaffold write` carries out the actions and `--check`
prints them, so the report cannot drift from what a run does. The default mode stays
all-or-nothing: with any file existing, every planned file's action is `refuse`, including the new
ones, because nothing would be written.

`--skip-existing` keeps the existing check for what counts as existing (`path type`, so a dangling
symlink is in the way). A path whose parent is not a directory still fails at the write, as today.

### `--check`, never `--dry-run`

AGENTS.md records that the tool deliberately has no `--dry-run` flag, and the same word on one
subcommand would invite a "fix". The check exits 0 whatever it finds, because exit 2 is reserved for
the operator's arguments and environment, and a repository that differs from its templates is
normal. It prints to stdout, the one exception to `init` keeping stdout empty; the existing
requirement concerns runs that write, so it needs no change. A target directory that does not exist
is not created, and every file is `new`.

### The pin warning reuses `upgrade`

The warning runs the `upgrade` candidates through `upgrade-line` in memory and names files that would
change, so there is no second definition of a pin. `upgrade-line` always strips a digest, so a line
whose only change is losing its digest is not stale: compare with the digest removed from both sides.
Warning alone was chosen over refusing: mixed pins work, and `upgrade` fixes them in one step. It
reads the same files `upgrade` reads and no others.

### The example is disabled in the template, unconditionally

Writing it enabled in a fresh repository and disabled otherwise would need a second template or a
conditional, and templates deliberately have neither. `replace-me` stays, so an operator who removes
`disabled: true` without choosing a repository still gets exit 3 naming the placeholder.

### No guard for an all-disabled repository

`run-configs.sh` could fail when every file is disabled, since each summary records it. It was
rejected: pausing every file would then turn the pipeline red, and pausing must stay simple. The
first-run failure on the placeholder or missing `NEXUS_URL` still stands, because `config resolve`
runs before the disabled check. AGENTS.md must record this so the guard is not added later as a fix.

## Risks / Trade-offs

- [A repository with its URL set and only disabled files passes doing nothing] → Accepted. The tool
  says so on stderr for each file, the report's summary carries `disabled: true`, and the comment in
  the example explains the copy step.
- [An operator's copy keeps `disabled: true` by mistake, so a real target is silently not cleaned] →
  Same signals. The example's comment names removing the line as part of the copy step.
- [A real configuration kept in `example.yaml`, as the old flow invited, is replaced by
  `--only example --force` and that cleanup stops] → `--check` shows the file as `differs`, and the
  `--force` help text warns about this group.
- [`--only env --force` overwrites an operator's `.gitignore`] → Existing behaviour of `--force`,
  now easier to reach. Same help text.
- [`--skip-existing` keeps a `.gitignore` that lacks varlock's value files, so a password can be
  committed] → Kept paths are listed on stderr. No file-specific check: `init` never reads an
  existing file's meaning, and this would be its first special case.
- [`--check` on the pipeline mixes the operator's edits with the release's changes] → Reported only
  as `differs`. A later diff would have the same limit.

## Migration Plan

No action is required. Existing repositories keep their enabled `example.yaml`: `upgrade` moves its
pins only, and it keeps failing on `replace-me` until edited, as before. An operator who wants the new
file runs `init --ci <system> --only example --force`. Rollback is the previous release: nothing it
reads changes shape, and `disabled` is already a supported key.
