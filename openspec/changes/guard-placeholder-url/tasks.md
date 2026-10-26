# Tasks

## 1. Test hosts off the reserved names

- [ ] 1.1 Replace `nexus.example.invalid` and `from-env.invalid` in `tests/` with `nexus.test` and `from-env.test` (and any other `.invalid` URL host used as an accepted URL), leaving fixtures untouched; verify `nu tests/run-tests.nu` passes unchanged in behaviour and `grep -rn '\.invalid\|example\.com' tests/*.nu` lists only uses that are not URLs given to the tool (such as the `$schema` value in `test-config-file.nu`)

## 2. The refusal

- [ ] 2.1 In `config resolve`, after the `http` prefix check, take the host with `url parse`, lower-case it, drop one trailing dot, and refuse it when it equals or ends in `.` plus `example`, `example.com`, `example.net`, `example.org` or `invalid`, with a usage error naming the source (`$url.name`), quoting the address, calling it a placeholder and saying to set it to the operator's Nexus; verify with new tests in `tests/test-config.nu` covering each spec scenario: each source (flag, `NEXUS_URL`, file), every reserved name with case, port and trailing-dot variants, the look-alikes `example.company.com`, `myexample.com`, `nexus.examples.org`, and the local names `localhost`, `nexus.localhost`, `nexus.test`, `127.0.0.1`, `[::1]`
- [ ] 2.2 Add CLI tests in `tests/test-cli.nu`: `NEXUS_URL=https://nexus.example.com` with an invalid keep count exits 2 with the placeholder message, using a fetch stub that fails the test on any request; the same `NEXUS_URL` with `--version` and with `init --ci gitlab` into a temporary directory exits 0; verify they pass
- [ ] 2.3 Add a test that runs each generated pipeline's URL — the `NEXUS_URL` value read from the GitLab and both Jenkins templates — through `config resolve` and expects the placeholder refusal, so a template that drifts to an unrefused placeholder fails the suite; verify it passes and fails when the template value is changed to `https://nexus.company`

## 3. Documentation

- [ ] 3.1 README "Getting started" and "Configuration": say that a reserved example or `.invalid` host is refused with exit 2 before any request, and that the generated pipelines' `https://nexus.example.com` must be replaced; verify the README renders and `tests/test-examples.nu` still passes
- [ ] 3.2 If a pipeline header comment is reworded to mention the check, re-render with `nu tools/render-examples.nu` and verify `tests/test-examples.nu` passes; otherwise verify that no template changed

## 4. Integration

- [ ] 4.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and verify it passes; verify `nu -c 'use nexus-cleanup'` still prints nothing
- [ ] 4.2 Run `openspec validate guard-placeholder-url --strict` and verify it passes

## Workflow follow-up

- Commit as `feat:` so the refusal appears in the changelog.
- Archive the change after merge.
