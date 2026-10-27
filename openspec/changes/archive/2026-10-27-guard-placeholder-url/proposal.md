## Why

Three of the four pipelines `init` writes — GitLab and both Jenkins variants — set
`NEXUS_URL: https://nexus.example.com` for the operator to replace. A pipeline run before it is
replaced does not fail on the URL: it resolves a name that leads nowhere, retries four times
with backoff and exits 3 with "listing repositories failed", which reads as an outage of a
Nexus that was never configured. The fault is the operator's configuration, and the tool can
tell so before it sends a single request.

The same holds for a URL that is not one at all. The only check today is that the value starts
with `http`, so `http//nexus`, `https://` or `httpx://nexus` pass it and fail later at the first
request, with exit 3, as if Nexus were down.

## What Changes

- **The URL must parse, with an `http` or `https` scheme.** The resolved value is parsed once;
  a value that does not parse — no host, a malformed separator — or whose
  scheme is anything else is refused with exit 2 before any request, naming its source. This
  replaces the `http` prefix check, whose message already promised "an http or https URL".
- **A placeholder URL is a usage error.** After the URL is resolved from the flag, `NEXUS_URL`
  or the configuration file, a host that is one of the names reserved for documentation and
  for invalid use — `example`, `example.com`, `example.net`, `example.org` or `invalid`, or any
  name under them — is refused with exit 2 before any request. Such a host can never be a real
  Nexus, so the check rejects nothing that could have worked.
- **The message says where the value came from and what it is.** It names the source the tool
  already tracks (`--url`, `NEXUS_URL`, or `'url' in <file>`), says the address is a
  placeholder, and tells the operator to set it to their Nexus — in the CI variables when it
  came from the environment.
- **Local development names stay allowed.** `.test`, `.localhost`, `localhost` and IP addresses
  are reserved too, but they are real local setups — including the reference instance — and are
  not refused.
- **The generated pipelines keep `https://nexus.example.com`.** It is now caught by the check,
  so an unedited pipeline fails in its first dry run naming the placeholder, as an unedited
  `configs/example.yaml` already does for its `replace-me` repository.
- **Test hosts follow one rule.** `.invalid` means never usable: the recorded fixtures keep
  `nexus.example.invalid` as their redaction placeholder, which the check now refuses outright.
  `.test` means accepted but never contacted: tests and configuration fixtures that pass a
  `.invalid` URL to reach a later validation move to a `.test` host. AGENTS.md records the rule.
  New tests cover each reserved name, a subdomain of one, each source and the allowed local
  names.

Non-goals: resolving the host, contacting it, or checking that it is a Nexus before the run;
refusing any URL that parses with an `http` or `https` scheme and a host outside the reserved
placeholder names.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `nexus-cleanup/cli`: two new requirements, each applied to the URL from any source with exit 2
  before any request: the URL must parse with an `http` or `https` scheme, and a placeholder
  Nexus URL is refused.
- `nexus-cleanup/config-repository`: the generated pipeline's placeholder URL makes an unedited
  pipeline fail its first dry run with a usage error naming the placeholder, rather than with an
  API failure.

## Impact

- **Code**: `nexus-cleanup/config.nu` (`config resolve`, replacing the `http` prefix check).
- **Tests**: about 60 uses of `.invalid` hosts in nine files — `test-api`, `test-cli`,
  `test-config`, `test-config-file`, `test-config-schema`, `test-end-to-end`, `test-report`,
  `test-run`, `test-scaffold` — and the configuration fixtures `tests/fixtures/config/full.yaml`
  and `connection.yaml` move to `.test` where the URL is meant to be accepted. The recorded API
  fixtures and `PLACEHOLDER_HOST` are unchanged.
- **AGENTS.md**: the test host convention, under "Tests".
- **Schema**: unchanged. The `url` key's pattern stays looser than the tool, as the schema must.
- **Docs**: README "Getting started" and the pipeline headers mention that the placeholder URL
  must be replaced; the example trees are re-rendered if a header changes.
- **Behaviour**: a run that previously failed with exit 3 against a placeholder host, an
  unparseable URL or a non-http scheme now fails with exit 2 and no network traffic. No run that
  could have succeeded is affected.
