## Context

See proposal.md for why. What exists today:

- `config resolve` resolves the URL first — flag, then `NEXUS_URL`, then the file's `url` — and
  keeps the source's name for messages (`--url`, `NEXUS_URL`, `'url' in <file>`). Its only check
  is that the value starts with `http`. The file loader separately refuses a `url` carrying
  credentials.
- The GitLab and both Jenkins templates set `NEXUS_URL` to `https://nexus.example.com` in the
  pipeline file. The Forgejo template reads `${{ vars.NEXUS_URL }}`, which is empty when the
  variable is unset, and the tool already refuses an empty URL.
- About 60 places in nine `tests/*.nu` files, and the configuration fixtures
  `tests/fixtures/config/full.yaml` and `connection.yaml`, use `nexus.example.invalid`,
  `from-env.invalid` or `from-file.invalid` as a URL that is never contacted, most of them
  through `config resolve`.
- The recorded API fixtures carry `nexus.example.invalid` (`PLACEHOLDER_HOST` in
  `tools/record-fixtures.nu`) in place of the instance's host, about 600 times;
  `tests/test-fixtures-clean.nu` asserts it is the only Nexus host there. They never reach
  `config resolve`: the tests' fetch stubs route by path and ignore the host.

## Goals / Non-Goals

**Goals:**

- One check, applied to the resolved value whatever its source, before the first request.
- No false refusal of an address that could reach a real Nexus.

**Non-Goals:**

- DNS resolution or a probe request: either one makes the check depend on the network, and a
  name that resolves is not thereby a Nexus.

## Decisions

### Parse once, before the placeholder check, and require `http` or `https`

The resolved value is parsed with Nushell's `url parse` inside `try`. A failure is a usage
error naming the source and quoting the value, instead of the unhandled "Unsupported input"
error `url parse` raises — which would exit 1 and read as a crash. A parse failure and a wrong
scheme share one message, so an operator never has to tell them apart. Observed on the pinned
0.115.1 and on 0.116.1: `http//nexus` and `https://` fail to parse, as do `http://:8081` and
`https://nexus.test:99999` on both (checked in the pinned image during implementation; the
suite tests them). A parsed value whose scheme is not `http` or `https` (such as
`httpx://nexus`) is refused with the message the prefix check already uses ("must be an
http or https URL, got '…'"), so existing assertions on that wording keep holding. The
`str starts-with "http"` check is removed: the scheme check covers it and is exact.

The placeholder check reads the host from this parse, so the value is parsed once. Whatever
`url parse` accepts with an `http` or `https` scheme and a host is accepted here; the tool does
not add its own URL grammar.

Alternative: a regular expression for the URL shape. Rejected: it would be a second parser that
disagrees with the one the host is taken from, and with `http get` at the edges.

### Match the host's labels against the reserved names, nothing looser

The host is taken from the parse above (so a port, IPv6 brackets or a path cannot confuse it),
lower-cased and stripped of one trailing dot, then refused when it equals a
reserved name or ends in `.` plus one: `example`, `example.com`, `example.net`, `example.org`,
`invalid`. Matching on whole labels is what keeps `example.company.com` and `myexample.com`
acceptable.

Alternatives: matching only the literal template value `https://nexus.example.com` would miss an
operator's own placeholder (`https://nexus.example.org`, `https://changeme.invalid`) for no
benefit; matching any host containing `example` would refuse real hosts.

### `.test`, `.localhost` and addresses stay allowed

They are reserved as well, but for real local use: the reference instance is reached as
`localhost`, and `.test` names are a common way to run a Nexus in a lab. Refusing them would
break legitimate runs to catch placeholders nobody writes.

### Placed after source resolution, before every other check

Both checks run where the `http` prefix check runs today — parse and scheme first, then the
placeholder — so their messages can name the source and they fire before keep, timeout or
pattern errors: an unedited pipeline gets the one message that explains it. Each is a usage
error (exit 2) like every other configuration fault. The configuration file loader's own checks
(unknown keys, a `url` carrying credentials) still run earlier, as they do today.

### Templates keep `https://nexus.example.com`

It is now refused, which is the point: the unedited pipeline fails in its first dry run naming
the placeholder, the same pattern as `replace-me` in the starting configuration. A distinctive
spelling such as `https://replace-me.invalid` was considered; `nexus.example.com` reads as an
address to fill in and is equally caught, and keeping it leaves the rendered examples unchanged.

### Test hosts: `.invalid` is never usable, `.test` is accepted but never contacted

The two reserved names get two meanings in the suite, and each host is chosen by meaning:

- **`.invalid` — never usable.** The recorded fixtures' redaction placeholder
  `nexus.example.invalid`, and inputs the URL checks must refuse. The placeholder stays as it is,
  and that is now a guarantee rather than a coincidence: a redacted URL that ever reached a
  configuration would be refused before any request.
- **`.test` — accepted, never contacted.** Every URL a test expects the tool to accept:
  `https://nexus.test`, `https://from-env.test` and `https://from-file.test` where the source
  matters, in `tests/*.nu` and in the configuration fixtures under `tests/fixtures/config/`, which
  go through `config resolve`. `tests/test-api.nu` builds its client without `config resolve`
  and could keep its URLs, but is moved too, so the rule needs no exception.

`tests/test-fixture-redaction.nu` keeps `nexus.internal.example.org` as the stand-in for a real
host the recorder must replace: it is the redactor's input, never given to the tool.

Alternative: everything on `.test`, the redaction placeholder included. Rejected: it rewrites
about 600 lines of recorded fixtures for uniformity alone — the files whose diffs are meant to
show only what Nexus changed — and makes a redacted URL look like a working address.

## Risks / Trade-offs

- [An internal DNS zone that serves a real Nexus under a reserved name] → Such a name violates
  RFC 2606 and RFC 6761 and cannot be relied on elsewhere either; the message says the address is
  reserved, which tells the operator why. No override is offered: an escape hatch for a
  configuration mistake would be used to silence it.
- [An operator's placeholder outside the reserved names, such as `https://nexus.company`] → Not
  caught, and fails as today with exit 3. The check removes the common case, not every case.
- [`url parse` accepts an odd shape, such as `http:nexus` parsing to host `nexus`] → Accepted as
  today and left to the request. The check refuses what the parser rejects, not what looks
  unusual.
- [A Nushell upgrade changes what `url parse` accepts] → The parse tests run in the pinned image,
  so a Nushell update pull request that changes the behaviour fails its required checks.
