# Tasks

Commit each group as a Conventional Commit, and run the suite with `nu tests/run-tests.nu` in the
pinned image before calling a group done.

## 1. Disabled example

- [x] 1.1 In `templates/common/configs/example.yaml`, set `disabled: true`, keep `replace-me`, and rewrite the comments as the copy step (copy, name a real repository, remove the `disabled` line); verify `config load` and `config resolve` accept the rendered file and report `disabled` true
- [x] 1.2 Replace the tests in `tests/test-scaffold.nu` that expect an enabled example: an unedited example sends no request and exits 0; with the `disabled` line removed it still fails naming `replace-me`; verify the suite passes
- [x] 1.3 Add a case to `tests/test-run-configs.nu` where the example sits beside a real file and that file's exit code ends the job; verify it passes with `run-configs.sh` unchanged
- [x] 1.4 Run `nu tools/render-examples.nu` and verify `tests/test-examples.nu` passes and the example diffs are only that file's lines
- [x] 1.5 Update the README's first-steps text (the `replace-me` paragraph) to the copy flow and verify the paragraph matches the rendered comment
- [x] 1.6 In `AGENTS.md`, rewrite the `replace-me` bullet under `init`, and record the deliberate decisions that the example ships disabled and that `run-configs.sh` has no all-disabled guard, each with its reason; verify `grep -n "fails its first dry run" AGENTS.md` finds nothing

## 2. Groups and `--only`

- [x] 2.1 Add a `group` field to each `scaffold plan` record, from a table beside `COMMON`, and verify a test maps every planned file of every CI system, editor and environment tool to its group from the design table
- [x] 2.2 Add `--only` to `scaffold plan` and `scaffold init-args` as a repeatable flag, with usage errors for an unknown group and for a group the selection leaves empty; verify with tests for one group, several groups and both errors
- [x] 2.3 Wire `--only` through `main init` and verify in a child process that `init --ci gitlab --only runner --force` overwrites only `ci/run-configs.sh`, and that `init --ci gitlab --only base` refuses on `.editorconfig` without listing an existing `.gitlab-ci.yml`
- [x] 2.4 Verify `tests/test-examples.nu` still passes, so that the added field changes no rendered example

## 3. `--skip-existing`

- [x] 3.1 Compute each planned file's state and action in one place, and make `scaffold write` carry out those actions, with existing refuse and `--force` behaviour unchanged; verify the existing `scaffold write` tests pass unedited
- [x] 3.2 Add `--skip-existing` to `scaffold write` and `scaffold init-args`, listing kept paths on stderr, with `--skip-existing --force` a usage error; verify with tests for added files, nothing missing, a dangling symlink kept, a removed example restored, and the combined flags
- [x] 3.3 Update `scaffold init-help` and the unknown-flag message for `--only` and `--skip-existing`, including the warning that forcing the `example` and `env` groups can overwrite an operator's real configuration or `.gitignore`; verify a test finds each option in `init --help`
- [x] 3.4 Document both options in the README's "Nothing is overwritten unasked" text and beside the `init --force` alternative in Upgrading; verify the documented commands run in a temporary directory

## 4. Pin warning

- [x] 4.1 Reuse the `upgrade` candidates and `upgrade-line` to find stale files without writing, ignoring a digest on a pin that names the running version; verify with tests for an older pipeline, an older `configs/prod.yaml`, agreeing pins, an empty directory, and a digest on the running version
- [x] 4.2 Warn from `init` after writing, on stderr, naming each file and advising `upgrade`; verify in a child process that the file is unchanged and the exit code is 0
- [x] 4.3 Add the order "`upgrade`, then `init --skip-existing`" to the README's Upgrading section and verify the result has no stale pin and no warning

## 5. `--check`

- [x] 5.1 Add `--check` to `init`, printing one line per planned file (path, group, state, action) to stdout from the decision in 3.1, writing nothing and creating no directory; verify with tests for each scenario in the spec, including that the target directory is not created
- [x] 5.2 Add `--check` to `scaffold upgrade` and `scaffold upgrade-args`, printing each file it would change to stdout, with the same warnings and no write; verify with tests for stale pins, nothing to upgrade and a digest warning
- [x] 5.3 Update both help texts and the README, and record in `AGENTS.md` why the option is `--check` and not `--dry-run` and that the groups follow what is safe to overwrite; verify a test finds `--check` in both `--help` outputs

## 6. Integration

- [x] 6.1 In a temporary directory, write a repository with `init` at an older pinned version, then run `upgrade --check`, `upgrade`, `init --skip-existing --check` and `init --skip-existing --editor intellij`; verify each step's stdout, stderr and exit code, and that no operator edit is lost
- [x] 6.2 Run `nu tests/run-tests.nu` in `ghcr.io/nushell/nushell:0.116.1-alpine`, verify it passes, and verify `nu -c 'use nexus-cleanup'` prints nothing

## Workflow follow-up

- Describe the new example flow in the release notes, because the `BREAKING` change is visible only to operators who refresh the file.
- Archive the change after the pull request has merged.
