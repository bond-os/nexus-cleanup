# Spec Delta

## MODIFIED Requirements

### Requirement: Starting configuration file

`init` SHALL write `configs/example.yaml`, beginning with a YAML language server modeline that
references the pinned schema. The file SHALL be accepted by the tool's configuration loading and
valid against the schema, and SHALL select a placeholder repository that cannot exist, so that a
pipeline run before it is edited fails naming that placeholder. The file SHALL describe, in a
comment, how to disable it without deleting it.

#### Scenario: Example accepted and valid

- **WHEN** `configs/example.yaml` is loaded by the tool that wrote it and validated against the pinned schema
- **THEN** both accept it

#### Scenario: Unedited example fails loudly

- **WHEN** the generated pipeline runs before `configs/example.yaml` is edited
- **THEN** the dry-run job fails with an error naming the placeholder repository
- **AND** no deletion request is sent

#### Scenario: Disabling documented

- **WHEN** an operator reads `configs/example.yaml`
- **THEN** a comment shows `disabled: true` and states that it skips the file on every run until removed
- **AND** the key is commented out, so the unedited example is not disabled
