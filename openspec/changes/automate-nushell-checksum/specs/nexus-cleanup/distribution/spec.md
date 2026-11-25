# Spec Delta

## ADDED Requirements

### Requirement: Nushell checksum repairs are narrow and verifiable

When the generated Forgejo pipeline's Nushell download checksum is stale in an eligible
Renovate Nushell update, maintenance automation SHALL repair that update from the release
asset and SHALL leave every other pull request unchanged.

#### Scenario: Eligible Renovate update has only a stale checksum

- **WHEN** the required checksum check fails for an open same-repository pull request from
  `renovate[bot]`
- **AND** the pull request is the grouped Nushell update on the established Renovate branch
- **AND** its changed files are all within the documented Nushell pin set
- **THEN** automation downloads the exact asset named by the Forgejo template and calculates
  its SHA-256
- **AND** it changes the checksum in both the template and generated example
- **AND** it preserves the template's Nushell version and all unrelated file contents

#### Scenario: Update is not eligible

- **WHEN** a failed checksum check belongs to any other actor, repository, branch, or changed
  file set
- **THEN** automation makes no commit and no push
- **AND** the failed check remains visible for maintainer review

#### Scenario: Check failure is not a stale checksum

- **WHEN** the declared Nushell version and pinned checksum already agree, or the release asset
  cannot be retrieved and verified
- **THEN** automation makes no commit and no push
- **AND** it reports why the automatic repair was refused

### Requirement: A checksum repair preserves the runtime update's commit and gates

A checksum repair SHALL become part of the original Nushell dependency update rather than a
second release-visible change, and it SHALL rerun rather than waive the required checks.

#### Scenario: Repair succeeds

- **WHEN** eligible automation changes the stale checksum values
- **THEN** it amends the existing dependency update commit without changing its message
- **AND** the amended commit retains the original dependency update's parent
- **AND** it force-pushes only the verified head revision of the established Renovate branch
- **AND** it starts a fresh run of the complete tests workflow
- **AND** it does not merge the pull request or approve the required checks

#### Scenario: Branch changed during repair

- **WHEN** the established Renovate branch has advanced beyond the revision that was verified
- **THEN** the update push is refused
- **AND** automation does not overwrite the newer branch head
