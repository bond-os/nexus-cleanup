# Tasks

## 1. Unknown-repository message

- [ ] 1.1 Change the error in `api select-repositories` for a name missing from the listing to say the repository does not exist on this instance or is not visible to this user; update the assertions in `tests/test-api.nu` (and any CLI test matching the old text); verify they pass

## 2. Privileges, established on the reference instance

- [ ] 2.1 On the reference Nexus 3.96, create a test role and user with no privileges and run the tool as that user against `yum-proxy-resources.ovirt.org`, `apt-proxy-deb.debian.org` and `packer-bases` (with `--allow-hosted` and a `--from-path`), adding one privilege at a time until a dry run completes; record per call which of `browse` / `read` it needed and what a missing privilege looked like (the unknown-repository error, a 403 exit 3, the apt scope falling back); verify the notes cover all four calls
- [ ] 2.2 Repeat with `--execute --max-deletions 1` to find the privilege `DELETE /v1/components/{id}` needs, and confirm that a delete privilege granted with a wildcard repository (`nx-repository-view-raw-*-delete`) also allows deleting from the raw hosted repository; restore any deleted component by re-fetching through the proxy or re-uploading the hosted file; delete the test role and user afterwards
- [ ] 2.3 Write the README "Nexus permissions" section from those notes: the call-to-privilege table with the Nexus version it was checked on, the two roles (`nexus-cleanup-dry-run`, `nexus-cleanup-execute`) as `POST /service/rest/v1/security/roles` bodies and as UI steps with one user each, why delete privileges name repositories, the `--pattern` conflict, and what a missing privilege looks like; verify each role body by creating it on the reference instance with the documented request and running a dry run and a capped execute as its user

## 3. Separate credentials for the execute job

- [ ] 3.1 README, in the permissions section: the edit per CI system that gives the execute job the execute user — GitLab `environment:` plus environment-scoped variables, Jenkins a second credential id in the execute stage, Forgejo differently named secrets in the execute step with its weaker isolation stated — and the warning that `init --force` rewrites the edit; verify each snippet against the matching file under `examples/<system>/` (the edited line exists there as quoted)

## 4. Upgrading a configuration repository

- [ ] 4.1 Write the upgrade script: inside the image, read the version from `nexus-cleanup --version` and, in whichever of `.gitlab-ci.yml`, `Jenkinsfile`, `.forgejo/workflows/nexus-cleanup.yml`, `configs/*.yaml`, `configs/*.yml`, `.vscode/settings.json` and `.idea/jsonSchemas.xml` exist, rewrite image pins under any registry (`nexus-cleanup` after `/`, a quote or whitespace, then `:` and a digit or `@sha256:`) keeping `X.Y` or `X.Y.Z` precision, replace both digest forms by the new tag with one stderr warning per line naming the file and advising to re-add a verified digest, rewrite `NEXUS_CLEANUP_VERSION: v<version>` and `nexus-cleanup/v<version>/schema/`, and copy `NU_VERSION` and `NU_SHA256` from `/opt/nexus-cleanup/nexus-cleanup/templates/ci/forgejo/.forgejo/workflows/nexus-cleanup.yml` only while the workflow's `asset=` line names `x86_64-unknown-linux-musl`, otherwise leaving them and saying so on stderr; print each changed file and exit 0. Verify by running it through the current release image against copies of every `examples/<system>/`:
  - with every pin set to `0.0.1`, and the Forgejo `NU_VERSION` and `NU_SHA256` set to an older release's values: the result equals the rendered example apart from the release markers
  - with the Forgejo asset switched to `aarch64-unknown-linux-musl`: `NU_VERSION` and `NU_SHA256` are unchanged and stderr says to update them by hand
  - with the GitLab image pinned as `nexus-cleanup:0.0`: it becomes the new `X.Y`
  - with the image pinned as `nexus-cleanup:0.0.1@sha256:<64 hex>` and as `nexus-cleanup@sha256:<64 hex>`: both become the new `X.Y.Z` tag, stderr carries one warning per line, and the exit code is 0
  - with the image under a mirror prefix (`nexus.corp:5000/bond-os/nexus-cleanup:0.0.1`): the prefix is kept and the tag moves
  - in every case the GitLab job names `nexus-cleanup:dry-run`, `nexus-cleanup:execute` and `.nexus-cleanup:` are unchanged
- [ ] 4.2 README: an "Upgrading" section with the command (`docker run … --entrypoint nu ghcr.io/bond-os/nexus-cleanup:X.Y.Z -c '…'`) between `x-release-please-start-version` / `-end` markers, followed by the rootless sentence from "Getting started" (`--userns=keep-id` for rootless Podman, `--user 0:0` for rootless Docker, linking "Who the container runs as"); before the command, that it supports tag pins only and replaces a digest pin by the tag with a warning, and how to re-add a verified digest (`docker buildx imagetools inspect`, `gh attestation verify`); that Forgejo's Nushell pins move with it unless the workflow uses the arm64 binary; the advice to read `CHANGELOG.md` and `git diff` first, `init --force` as the alternative, and a pointer to a Renovate regex manager over the image and schema patterns; make the "Pin an exact version, or a digest" paragraph link to this section; replace the inline bump advice in "Getting started", "Editor support" and "CI" with links to it; verify the marked block holds exactly one X.Y.Z, on the image line, and that `tests/test-examples.nu`'s release-marker checks still pass

## 5. Integration

- [ ] 5.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and verify it passes
- [ ] 5.2 Run `openspec validate document-least-privilege-and-upgrades --strict` and verify it passes

## Workflow follow-up

- Commit the message change as `fix:` and the README sections as `docs:`.
- Archive the change after merge.
