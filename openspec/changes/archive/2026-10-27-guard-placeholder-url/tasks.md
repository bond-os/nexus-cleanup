# Tasks

## 1. Test hosts off the reserved names

- [x] 1.1 Replace every URL host that a test expects to be accepted with a `.test` host: `nexus.example.invalid`, `from-env.invalid` and `from-file.invalid` become `nexus.test`, `from-env.test` and `from-file.test` in `tests/*.nu` and in the hand-written configuration fixtures `tests/fixtures/config/*.yaml` (`full.yaml`, `connection.yaml`); leave the recorded API fixtures under `tests/fixtures/<format>/` and `tests/fixtures/repositories.json`, `PLACEHOLDER_HOST` in `tools/record-fixtures.nu`, and the redaction input host in `tests/test-fixture-redaction.nu` unchanged; verify `nu tests/run-tests.nu` passes unchanged in behaviour, and that `grep -rn '\.invalid' tests/*.nu tests/fixtures/config` lists only uses that are never accepted as a Nexus URL (the `$schema` values, references to `PLACEHOLDER_HOST`)

## 2. The refusals

- [x] 2.1 In `config resolve`, replace the `http` prefix check: parse the resolved value with `url parse` inside `try`, and raise the usage error `<source> must be an http or https URL, got '<value>'` when parsing fails, the host is empty, or the scheme is neither `http` nor `https`; keep the parsed record for 2.2; verify with new tests in `tests/test-config.nu` covering each spec scenario of "Nexus URL must parse as http or https": `http//nexus` from `NEXUS_URL`, `https://` from the flag, `http//nexus` from a file (each naming its source), `httpx://nexus.test` and `ftp://nexus.test`, the accepted `https://nexus.test`, `http://nexus.test:8081/`, `https://nexus.test/nexus` and `http://[::1]:8081`, and an unparseable URL with an invalid keep count reporting the URL; also record which of `http://:8081` and `https://nexus.test:99999` the pinned image refuses, and test those it does
- [x] 2.2 In `config resolve`, after 2.1, take the host from the parsed record, lower-case it, drop one trailing dot, and refuse it when it equals or ends in `.` plus `example`, `example.com`, `example.net`, `example.org` or `invalid`, with a usage error naming the source (`$url.name`), quoting the address, calling it a placeholder and saying to set it to the operator's Nexus; verify with new tests in `tests/test-config.nu` covering each spec scenario: each source (flag, `NEXUS_URL`, file), every reserved name with case, port and trailing-dot variants, the look-alikes `example.company.com`, `myexample.com`, `nexus.examples.org`, and the local names `localhost`, `nexus.localhost`, `nexus.test`, `127.0.0.1`, `[::1]`
- [x] 2.3 Add CLI tests in `tests/test-cli.nu`: `NEXUS_URL=https://nexus.example.com` with an invalid keep count exits 2 with the placeholder message, and `NEXUS_URL=http//nexus` exits 2 with the URL message, each using a fetch stub that fails the test on any request; `NEXUS_URL=https://nexus.example.com` with `--version` and with `init --ci gitlab` into a temporary directory exits 0; verify they pass
- [x] 2.4 Add a test that runs each generated pipeline's URL — the `NEXUS_URL` value read from the GitLab and both Jenkins templates — through `config resolve` and expects the placeholder refusal, so a template that drifts to an unrefused placeholder fails the suite; verify it passes and fails when the template value is changed to `https://nexus.company`

## 3. Documentation

- [x] 3.1 README "Getting started" and "Configuration": say that a URL that does not parse as http or https, and a reserved example or `.invalid` host, are refused with exit 2 before any request, and that the generated pipelines' `https://nexus.example.com` must be replaced; verify the README renders and `tests/test-examples.nu` still passes
- [x] 3.2 AGENTS.md "Tests": record the test host convention as a standing decision — `.invalid` hosts are never usable (the fixtures' redaction placeholder, inputs the URL checks must refuse), `.test` hosts are accepted but never contacted (base URLs in tests, URLs in configuration fixtures) — with the reason that the URL check then also refuses a redacted fixture URL; verify by reading the diff against design.md
- [x] 3.3 If a pipeline header comment is reworded to mention the check, re-render with `nu tools/render-examples.nu` and verify `tests/test-examples.nu` passes; otherwise verify that no template changed

## 4. Integration

- [x] 4.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and verify it passes; verify `nu -c 'use nexus-cleanup'` still prints nothing
- [x] 4.2 Run `openspec validate guard-placeholder-url --strict` and verify it passes

## Workflow follow-up

- Commit as `feat:` so the refusal appears in the changelog.
- Archive the change after merge.
