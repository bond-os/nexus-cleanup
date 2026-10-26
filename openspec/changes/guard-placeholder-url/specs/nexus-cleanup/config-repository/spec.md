# Spec Delta

## ADDED Requirements

### Requirement: Generated pipeline URL fails loudly until replaced

A pipeline that sets the Nexus URL in the pipeline file itself SHALL set it to an address the
tool refuses as a placeholder, so that a pipeline run before the operator replaces it fails with
a usage error naming that address rather than with an API failure. A pipeline that reads the URL
from a CI variable SHALL NOT supply a default for it.

#### Scenario: Unedited GitLab or Jenkins pipeline

- **WHEN** the pipeline written by `init --ci gitlab`, `--ci jenkins-docker` or `--ci jenkins-sh` runs its dry-run job before its Nexus URL is edited
- **THEN** each configuration file's run exits 2 with a message naming the placeholder address
- **AND** no HTTP request is made

#### Scenario: Forgejo variable unset

- **WHEN** the pipeline written by `init --ci forgejo` runs without the repository variable `NEXUS_URL`, and no configuration file sets `url`
- **THEN** each configuration file's run exits 2 with the error for a missing `NEXUS_URL`
