## Why

Every external component the project depends on is pinned exactly — GitHub Actions by commit
SHA, the commitlint and ajv-cli npm packages by version, and the Nushell runtime in seven places
across the image, CI, the README, AGENTS.md and the Forgejo template — and none of those pins
moves unless someone notices a release. Pins that are never moved stop being a decision and
become drift: security fixes in the actions that hold the release App's token are missed, and
the Nushell floor falls further behind each minor release, which makes the eventual jump larger
and riskier for a runtime that breaks compatibility between minors.

## What Changes

- **Renovate, as the hosted Mend Renovate GitHub App**, proposes dependency updates as pull
  requests on a weekly schedule, with a Dependency Dashboard issue listing what is pending, on
  Renovate's `config:best-practices` preset. Accepting a third party with write access to the
  repository is a deliberate trade for zero upkeep; see design.md.
- **The image's Nushell base is pinned by digest.** The `Containerfile` `FROM` and the CI test
  container become `ghcr.io/nushell/nushell:0.115.1-alpine@sha256:…`, the tag kept for
  readability. A tag is the one pin in the repository that upstream can move under it — actions
  are pinned by SHA, npm CLIs by immutable version, the Forgejo download by checksum. The README,
  AGENTS.md and the Forgejo template stay tag-only: they document a version, they build nothing.
- **Three update streams**, each its own pull request:
  - **Nushell runtime**: every Nushell pin moves in one pull request, committed as a `fix`, so
    it appears in the changelog and leads to a patch release — operators read the changelog to
    decide whether to move a pinned image, and a new runtime is exactly what they need to see.
  - **GitHub Actions**: SHA and version comment together, all actions in one pull request,
    committed as `ci` (hidden from the changelog).
  - **npm CLIs**: the commitlint pair always at one version, together with the hook command in
    AGENTS.md; ajv-cli separately; both committed as `ci`.
- **Nothing merges automatically.** Every update pull request passes the same required checks as
  any change and is rebase-merged by a maintainer.
- **A waiting period for npm**: npm packages are proposed only once they are three days old.
  Nushell has none: the digest can only come from the registry, ghcr publishes no release
  timestamps, and a wait that needs one would hold every Nushell update back forever. With no
  automerge a wait only delays when a pull request appears, not when anything merges.
- **Out of reach of the updater**: the tool's own release pins (`nexus-cleanup:X.Y.Z`, schema tag
  `vX.Y.Z`), which release-please owns; recorded fixtures; planning artefacts; and the pins in the
  `init` templates other than Nushell, which belong to the operators' repositories.
- **A new required check verifies the Forgejo template's Nushell checksum.** The template pins
  both `NU_VERSION` and the `NU_SHA256` of the tarball it downloads. Renovate can move the version
  but cannot compute the checksum, and the hermetic suite never downloads anything, so a Nushell
  update would otherwise pass CI and break every Forgejo pipeline generated from it.
- **AGENTS.md** gains a "Dependency updates" section recording these decisions, and the CI
  comment saying the Nushell pin "moves deliberately" is updated to say how it now moves.

Non-goals: automerge of any kind, self-hosting Renovate, updating pins inside repositories that
`init` generates, consolidating the repeated Nushell pin into one place, and raising the Nushell
floor as part of this change.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `nexus-cleanup/distribution`: adds requirements for how dependency updates are proposed and
  merged, how the Nushell runtime moves as one release-visible change, which pins the updater
  must never touch, the digest pin on the image's Nushell base, and the checksum check on the
  template's Nushell download; the merge gate gains that check as a required one.

## Impact

- **New config**: `renovate.json` in the repository root.
- **Image base**: `Containerfile` and the `test` job container gain the digest of the current
  `0.115.1-alpine` image, pinned in this change so the `image` check runs on it here rather than
  in Renovate's first pull request. The image's content does not change.
- **CI**: besides the digest, `tests.yml` gains a job that downloads the Nushell release asset
  named by the Forgejo template's `NU_VERSION` and verifies `NU_SHA256`; the comment on the
  pinned job image changes.
- **Docs**: AGENTS.md gains a "Dependency updates" section and lists the new required check under
  repository settings.
- **Repository settings (by hand)**: install the Mend Renovate App on the repository; add the new
  check to the `main` ruleset's required checks.
- **No change** to the tool, its module, its tests or the image contents.
