## Context

See proposal.md for why. What exists today:

- **Actions** are pinned as `owner/action@<sha> # vX.Y.Z` in `tests.yml`, `release.yml` and
  `commits.yml`.
- **npm CLIs** run through `npx` from exact versions held in workflow `env:` strings
  (`COMMITLINT_CLI`, `COMMITLINT_CONFIG` in `commits.yml`, `AJV_CLI` in `tests.yml`). The
  optional commit hook in AGENTS.md repeats the commitlint versions.
- **Nushell** is pinned as `ghcr.io/nushell/nushell:0.115.1-alpine` in the `Containerfile`, the
  `test` job container, the README's unreleased-revision command and AGENTS.md, as the bare
  floor `0.115.1` in AGENTS.md, and as `NU_VERSION: 0.115.1` plus `NU_SHA256` in the Forgejo
  template and its rendered copy under `examples/forgejo/`. `tests/test-examples.nu` requires the
  rendered copy to match the template byte for byte.
- **ghcr publishes every Nushell release as three tags**: bare (`0.115.1`), `-alpine` and
  `-bookworm`. Renovate reads no release timestamps from ghcr.
- The release-automation change listed "consolidating the repeated Nushell pin" as a non-goal;
  this change keeps it repeated and moves it as one instead.
- The `main` ruleset has no bypass actors and requires `test`, `config-schema`, `image` and
  `commitlint`. Changelog sections: `fix` shown, `ci` hidden.

## Goals / Non-Goals

**Goals:**

- One `renovate.json`, readable on its own, that produces exactly the three update streams in the
  spec and nothing else.
- Every Nushell pin follows a single version stream, so the pins cannot drift apart.
- What the image is built on and tested in cannot change without a pull request.
- A stale `NU_SHA256` turns a pull request red.

**Non-Goals:**

- Running anything after an update (re-rendering examples, recomputing checksums). The hosted
  app does not run arbitrary commands, and the design does not need it to.
- Digests anywhere other than the two references that build or test something.

## Decisions

### Hosted Mend Renovate App, not self-hosted, not Dependabot

The maintainer chose the hosted app and accepted that a third party holds write access to the
repository. It cannot land code on `main`: the ruleset requires a pull request with passing
checks and lists no bypass actors, and the App is not one either.

- **Self-hosted Renovate** in a scheduled workflow under its own narrow App was the alternative.
  It would keep the trust boundary inside the repository, at the cost of a second long-lived key
  to rotate and a workflow to maintain. It was rejected for upkeep.
- **Dependabot** cannot update versions held in free text: the `npx` strings, AGENTS.md, the
  README and `NU_VERSION`. It also cannot group pins of different kinds into one pull request.

### `config:best-practices`

Of what `best-practices` adds to `config:recommended`, only `docker:pinDigests` has an effect
here.

- **`docker:pinDigests`** applies to the image references Renovate's native managers see: the
  `Containerfile` `FROM` and the `test` job container. Those are exactly the two that build or
  test something.
- **No effect today:**
  - `helpers:pinGitHubActionDigests`: actions are already SHA-pinned. It would keep a newly added
    action from landing tag-pinned.
  - `:pinDevDependencies`, `:maintainLockFilesWeekly`: no `package.json`, no lock files.
  - `abandonments:recommended`: only flags long-unreleased packages on the dashboard.
- **`security:minimumReleaseAgeNpm`** duplicates the explicit npm wait. The explicit rule stays,
  so the wait survives a preset change.
- **`:configMigration`** opens a pull request when Renovate deprecates a key this config uses.

Text pins (README, AGENTS.md, template) are matched by regex rules that capture no digest, so the
preset cannot add one there.

### Nushell: one `docker` dependency, all seven pins

Every Nushell pin is the dependency `ghcr.io/nushell/nushell` from the `docker` datasource.

- **The two digest-pinned references** are read by the native `dockerfile` and `github-actions`
  managers, which maintain tag and digest together.
- **The text pins** are read by a custom regex manager: the README and AGENTS.md image references
  (`-alpine` tags), and the AGENTS.md floor and `NU_VERSION` in the template and example (bare
  tags). Docker versioning keeps each pin on its own tag flavour, and all flavours come from one
  upstream release.
- **Why `docker` for everything.** A digest exists only in the registry, so the digest-pinned
  references must track ghcr. Putting the text pins on the same datasource gives one version
  stream. Renovate also proposes only versions whose image tag exists, so the `test` job never
  points at a missing image.
- **Alternative rejected: `github-releases` for the text pins.** It has timestamps, but it would
  mean two version streams, and a three-day wait on one side only. The group pull request would
  then first appear with the digest-pinned references moved and the text pins not.

### No waiting period for Nushell

Renovate's default `minimumReleaseAgeBehaviour` is `timestamp-required`. On ghcr, which supplies
no timestamps, a Nushell `minimumReleaseAge` would hold every update back indefinitely.
`timestamp-optional` would make it a no-op. So Nushell has none.

This is acceptable because nothing is automerged. A wait would only delay when the pull request
appears; the maintainer still decides when it merges.

### Digest refreshes are runtime updates

When upstream re-pushes the pinned tag, Renovate proposes a digest-only change to the two
references. It belongs to the Nushell group and is committed as `fix`, because it changes the
base the released image is built on.

### Template and example are both matched, so the example check holds

`config:recommended` ignores `**/examples/**` and `**/tests/**`, and `ignorePaths` is not
mergeable. The config therefore sets its own `ignorePaths`: `tests/fixtures/**` and
`openspec/**`. That leaves `examples/` and the templates visible to the Nushell regex manager,
which rewrites the template and `examples/forgejo/` identically.

A package rule then disables the native managers under `nexus-cleanup/templates/**` and
`examples/**`. That also keeps `pinDigests` and the action-digest helper away from operator-owned
pins such as `node:24-bookworm` and `actions/checkout@v4`.

`enabledManagers` is limited to `github-actions`, `dockerfile` and `custom.regex`. Nothing else in
the repository is a dependency: the `gitlabci` manager would otherwise read
`examples/gitlab/.gitlab-ci.yml`, whose image pin release-please owns.

### npm CLIs: regex managers over the `npx` strings and the hook line

One regex manager matches `"<package>@<version>"` in workflow `env:` values. Another matches the
`-p <package>@<version>` arguments in AGENTS.md's hook command. A group rule keeps
`@commitlint/cli` and `@commitlint/config-conventional` in one pull request, because the hook and
the CI check must agree. ajv-cli is its own pull request. Both are three days old before they are
proposed.

### Commit types set explicitly

`semanticCommits: enabled`, scope `deps`. The Nushell group uses type `fix`, everything else
`ci`. The preset's default would be `fix(deps)` for every dependency, which would put each action
bump in the changelog. Renovate's default subjects fit the stock commitlint header limit.

### Checksum check: a `nushell-checksum` job in `tests.yml`

A job on `ubuntu-latest`:

1. Reads `NU_VERSION` and `NU_SHA256` from the template, which is the source; the example is held
   equal by `test-examples.nu`.
2. Downloads the same asset name the template installs.
3. Runs `sha256sum -c`.

On failure it prints the version, the pinned checksum and the actual checksum, so the fix can be
pasted. The job is maintenance glue (`curl`, `sed`, `sha256sum`), never part of the image or the
tool. It runs on every pull request and push, because a required check that is skipped blocks
merging. It also runs inside the release workflow's call to `tests.yml`. A GitHub download
outage then delays a release, and the fix is to re-run the job.

**Alternative rejected:** a step inside the `image` job. It would avoid a ruleset edit but hide an
unrelated failure under "image".

### Nushell PRs carry their own instructions

The Nushell group's PR body (`prBodyNotes`) tells the maintainer to:

- check that all seven pins moved;
- expect the checksum check to fail on a version change;
- amend the Renovate commit with the new `NU_SHA256` in both files rather than adding a second
  commit, so the changelog gets one line;
- push the branch with `--force-with-lease`.

Renovate stops rebasing a branch someone else has edited. That is what's wanted here.

### Initial digest pinned in this change

The `Containerfile` and `test` container get the current `0.115.1-alpine` multi-arch index digest
here, rather than in a "pin dependencies" pull request from Renovate. The `image` check then runs
on the pinned base inside this change. The commit is `build:` (hidden from the changelog), because
the content built is unchanged.

### Schedule and dashboard

`schedule: ["before 9am on monday"]` with `timezone: Europe/Warsaw`. The Dependency Dashboard
issue lists pending updates. No `automerge` key appears anywhere, and neither preset turns it on.

## Risks / Trade-offs

- [A Nushell minor breaks the tool] → The pull request is red. A maintainer fixes the code on the
  same branch, typically as further `fix` commits, or closes it. Renovate then proposes the next
  release and records the closed one as ignored on the dashboard.
- [Bare and `-alpine` tags published at different moments] → A run in that gap could open the
  group pull request with only some pins moved. The next run completes it, and the PR note asks
  the maintainer to check all seven before merging.
- [A Nushell release reaches GitHub but its tarball checksum is not yet in the template] → The
  `nushell-checksum` job is red until the amend.
- [Regex managers silently stop matching after a reformat] → The Dependency Dashboard lists every
  detected dependency. The implementation records the expected count (seven Nushell pins, two of
  them digest-pinned), and a local Renovate dry run checks it before merge.
- [Digest-only pull requests] → Rare for versioned Nushell tags. Each is a real change to what
  ships, so it is reviewed like one.
- [Third-party write access] → Accepted. The ruleset, the tag ruleset and release immutability
  still bound what the App can do: no landing on `main`, no moving `v*` tags.
- [The checksum job depends on github.com] → Accepted. It is a maintenance check; re-run on
  outage.

## Migration Plan

1. Merge this change. `renovate.json` lands, the base image is digest-pinned, and the new job
   starts running and passing.
2. The maintainer adds `nushell-checksum` to the `main` ruleset's required checks and installs
   the Mend Renovate App on this repository only. Because a config is already present, Renovate
   skips onboarding and opens the Dependency Dashboard.
3. Rollback: uninstall the App, or set `"enabled": false` in `renovate.json`. The digest pin and
   the checksum job are independent and stay.
