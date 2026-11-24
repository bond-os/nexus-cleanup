# Tasks

## 1. Candidate safety

- [x] 1.1 Add shared upgrade-candidate path validation that identifies terminal symlinks and
  symlinked parent directories without opening their targets, and verify it in
  `tests/test-scaffold.nu`
- [x] 1.2 Refuse `upgrade` and `upgrade --check` with a usage error before reading or writing any
  candidate when validation finds an unsafe path, and verify the all-or-nothing behavior and the
  unchanged external target
- [x] 1.3 Make stale-pin inspection skip unsafe candidates without reading their targets, and
  verify `init` does not warn from a symlinked candidate

## 2. Integration

- [x] 2.1 Run the focused scaffold suite and verify terminal-symlink, symlinked-parent, check-mode
  and stale-pin cases pass
- [x] 2.2 Run `nu tests/run-tests.nu` in the pinned Nushell image and verify all suites pass

## Workflow follow-up

- Archive the change after the fix is merged.
