## Context

See proposal.md for why. What exists today:

- The tool calls four endpoints (`api.nu`): `GET /v1/repositories`, `GET /v1/components`
  (paged), `DELETE /v1/components/{id}`, and — for apt repositories only — `GET
  /v1/repositories/apt/{type}/{name}`, whose failure is tolerated and leaves the implicit scope.
  `api select-repositories` reports a name missing from the listing as "does not exist on this
  instance".
- Credentials reach the pipelines as one pair for both jobs: GitLab CI/CD variables
  `NEXUS_USERNAME`/`NEXUS_PASSWORD`; the Jenkins credential id `nexus-cleanup` in both stages;
  Forgejo secrets of the same names in both steps.
- Pins `init` writes: the image tag in the GitLab and Jenkins pipelines, `NEXUS_CLEANUP_VERSION:
  vX.Y.Z` in the Forgejo workflow, and the schema address in `configs/*.yaml` modelines (or a
  `$schema` key), `.vscode/settings.json` and `.idea/jsonSchemas.xml`.
- The README is a release-please extra-file; a marked line moves its first X.Y.Z only.

## Goals / Non-Goals

**Goals:**

- Every privilege the README names is one the reference instance showed to be needed.
- One upgrade command that moves every pin `init` writes and can never write a version other
  than the image's own.

**Non-Goals:**

- Changing the templates to two credential pairs. The README shows the edit per CI system; making
  it the default is a later change if operators adopt it.

## Decisions

### Privileges are established empirically on the reference instance

A test role and user are created on the 3.96 instance and the tool is run as that user, adding
one privilege at a time, against a yum proxy, the apt proxy and the raw hosted `packer-bases`:
dry run first, then `--execute` with `--max-deletions 1`. The README then states, per call, the
privilege shown to be needed, including whether enumeration needs `read` in addition to
`browse`, and the Nexus version it was checked with. Writing the table from the documentation
alone was rejected: Nexus privilege semantics are under-documented and a wrong table is worse
than none.

### The README shows both roles as REST bodies and as UI steps

Each role — `nexus-cleanup-dry-run` (`browse` on the named repositories, plus apt admin `read`
where apt proxies are cleaned) and `nexus-cleanup-execute` (the same plus `delete`) — is shown
as a JSON body for `POST /service/rest/v1/security/roles` and as the equivalent path through
the UI, with one user per role. Repositories are named; a wildcard appears only in the text that
explains why it is avoided for delete.

### Separate execute credentials are documented as an edit per CI system

- GitLab: an `environment:` on the execute job and environment-scoped variables, building on the
  template's existing comment about protecting that environment.
- Jenkins: a second credential id in the execute stage's `withCredentials`.
- Forgejo: differently named secrets in the execute step. The README says plainly that this is
  weaker — every step of every workflow can read every repository secret — and that the
  per-repository delete privileges remain the real limit there.

The README warns that `init --force` rewrites these edits.

### Upgrade: one command run from the new image, which supplies the version itself

```
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" --entrypoint nu \
  ghcr.io/bond-os/nexus-cleanup:X.Y.Z -c '<script>'
```

The script asks the image for its version (`nexus-cleanup --version`) and rewrites, in the files
that exist among the pin locations above, every `nexus-cleanup:<version>`,
`NEXUS_CLEANUP_VERSION: v<version>` and `nexus-cleanup/v<version>/schema/` to that version. The
release appears once, as the image tag on the line release-please moves; the old version is
matched by pattern. The image cannot write a version it is not, and an operator cannot pass a
mismatched one. Running from the image needs no Nushell or `sed` on the host and avoids GNU/BSD
`sed -i` differences. The block sits between `x-release-please-start-version` and `-end`
markers, as the "Getting started" command does.

Alternatives: a `sed` one-liner (portability, and it would hold the version twice); a tool
subcommand (code and tests for a one-off edit, and it would need to know the operator's
repository layout). `init --force` stays documented for those who want to diff the whole tree.

### Renovate is named, not configured

The section closes with a pointer: operators who already run Renovate can add a regex manager
over the same three patterns with the image as its datasource. No `renovate.json` for operators
is shipped — it would be another template to keep current, for a minority of users.

## Risks / Trade-offs

- [Nexus changes privilege semantics in a later version] → The README names the version the
  table was checked with; "No Nexus version gating" means the tool will not adapt, the table is
  re-checked when the reference instance is upgraded.
- [The upgrade script rewrites something that only looks like a pin] → Patterns are anchored on
  `nexus-cleanup:`, `NEXUS_CLEANUP_VERSION: v` and `nexus-cleanup/v…/schema/`, and the advice to
  read `git diff` before committing stays.
- [`nexus-cleanup --version` inside `nu -c` fails because the launcher is not on that `PATH`] →
  Checked against the published image while writing the section; the launcher lives in
  `/usr/local/bin`.
