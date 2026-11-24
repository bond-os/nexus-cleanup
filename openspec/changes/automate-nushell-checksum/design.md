# Design

## Context

The `tests` workflow already downloads the exact Nushell asset used by the Forgejo template and
prints the real SHA-256 when the pin is stale. The repository's default workflow token is
read-only, Renovate creates one `fix(deps)` commit, and a push made with `GITHUB_TOKEN` does not
normally trigger `pull_request` workflows. The repair must therefore use a trusted workflow from
the default branch and explicitly start a new test run.

The workflow must not execute code from the Renovate branch. `actions/checkout` may place that
branch's files in a separate directory for data processing, while executable maintenance
scripts are loaded only from the default-branch checkout.

## Goals / Non-Goals

**Goals:**

- Remove the manual checksum copy, amend and rerun sequence from eligible Nushell updates.
- Preserve the existing required `nushell-checksum` check as an independent verification gate.
- Bound the token to one known branch, one open Renovate pull request, an exact failed job and
  an allowlist of Nushell pin files.
- Preserve the Renovate commit message and commit count.

**Non-Goals:**

- Approving, merging or automatically enabling any pull request.
- Repairing arbitrary dependency updates, user-authored pull requests or fork pull requests.
- Making a failed test pass, changing Nushell itself or loosening the required checks.
- Handling non-x86_64 assets or every possible future Renovate branch layout.

## Decisions

### Use a `workflow_run` workflow

A separate workflow listens for completed runs of `tests` and acts only when the run failed.
`workflow_run` runs the workflow definition from the default branch, so a pull-request payload
cannot replace the repair code merely by editing the branch under test.

The job requests only `contents: write` and `actions: write`. The repository-wide default remains
read-only, and the job receives no pull-request, issue or administration permissions.

Running the repair inside the existing pull-request job was rejected because a pull-request job
uses the untrusted revision and cannot safely elevate its token. A `pull_request_target` workflow
was rejected because this work is specifically conditional on the completed checksum job, and
`workflow_run` exposes that association directly.

### Validate the event before writing

The repair treats the event and every pull-request field as untrusted data. Before checkout or
mutation it will verify:

1. the completed workflow run is for `tests`, used `pull_request`, failed, and has the same
   repository as its head repository;
2. its head branch is exactly `renovate/nushell`;
3. its jobs include a failed job named `nushell-checksum`;
4. exactly one open pull request matches the run's head SHA, was authored by
   `renovate[bot]`, and is not from a fork;
5. the pull request's changed-file list is non-empty and contains only
   `Containerfile`, `.github/workflows/tests.yml`, `README.md`, `AGENTS.md`, the Forgejo
   workflow template and its generated example.

Eligibility failures exit successfully without writing anything, with a reason in the workflow
summary. Download and verification failures after eligibility exit as failures.

### Keep executable code on the default branch

The workflow first checks out the default branch and uses its pinned Actions dependencies and
maintenance script. It then checks out the verified pull-request SHA into a second directory
with credentials available for the later push. No script, workflow or shell command from the
pull-request tree is invoked.

A dedicated script owns parsing, download, checksum calculation and the exact replacement in
the template and rendered example. It accepts explicit file paths and refuses malformed,
missing, duplicate, disagreeing or non-numeric version/checksum values. The downloaded URL is
constructed from a strictly numeric dotted version and the fixed x86_64 musl asset name.

### Amend and conditionally push the exact verified revision

The script reports no repair if the template's version and checksum already agree. A successful
repair must leave the pull-request checkout with exactly the two intended checksum files
modified. The workflow stages those paths explicitly and amends the current commit with
`--no-edit`, preserving the `fix(deps)` message and the pull request's single-commit shape.

The push uses an explicit `--force-with-lease` value tied to the `workflow_run` head SHA, so
another update to the branch causes the push to fail instead of being overwritten. Only the
exact `renovate/nushell` ref is eligible as the destination.

After a successful push, the workflow dispatches `tests.yml` on that branch with
`actions: write`. Because workflow-token pushes do not reliably start checks, the explicit
dispatch is required. The push is already a complete, valid repair if dispatch fails; that step
fails visibly so a maintainer can rerun the tests.

### Verify the automation with refusal cases

Focused Nushell tests will exercise trusted script behavior with fixture files and a local
download stub, covering successful replacement, an already-correct checksum, malformed pins
and disagreement between the template and example. Workflow-level checks will assert the
default-branch checkout, exact trigger, least permissions, allowed branch/ref and lack of
merge/approval operations. The real checksum script remains the end-to-end verifier in Actions.

## Risks / Trade-offs

- [A broad or compromised `GITHUB_TOKEN` write path changes protected content] → run only from
  trusted default-branch code, validate all event inputs, constrain the changed files and use an
  exact-SHA force-with-lease push.
- [Renovate's branch layout changes] → refusal is safe; the allowlisted branch can be updated
  deliberately in a reviewed change.
- [Nushell changes its release asset naming or publication layout] → the repair and original
  checksum check both fail visibly; no files are committed.
- [A checksum asset is replaced upstream] → the required check computes and verifies the bytes
  from GitHub for that release at repair time; the workflow does not trust a checksum copied
  from the failed log.
- [A push succeeds but workflow dispatch fails] → the repaired commit remains auditable and the
  automation reports the failure so tests can be dispatched again.

## Migration Plan

Add the trusted workflow and script, update the dependency-update documentation and run the
focused and full test suites. Merge the workflow before relying on it. Existing Nushell pull
requests can be left unchanged or handled manually; subsequent eligible failures are repaired
automatically. Rollback is removal or disabling of the new workflow, which restores the
documented manual amend procedure without changing the underlying checksum gate.
