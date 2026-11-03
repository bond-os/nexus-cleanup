# Tasks

## 1. Unknown-repository message

- [x] 1.1 Change the error in `api select-repositories` for a name missing from the listing to say the repository does not exist on this instance or is not visible to this user; update the assertions in `tests/test-api.nu` (and any CLI test matching the old text); verify they pass

## 2. Privileges, established on the reference instance

- [x] 2.1 On the reference Nexus 3.96, create a test role and user with no privileges and run the tool as that user against `yum-proxy-resources.ovirt.org`, `apt-proxy-deb.debian.org` and `packer-bases` (with `--allow-hosted` and a `--from-path`), adding one privilege at a time until a dry run completes; record per call which of `browse` / `read` it needed and what a missing privilege looked like (the unknown-repository error, a 403 exit 3, the apt scope falling back); verify the notes cover all four calls
- [x] 2.2 Repeat with `--execute --max-deletions 1` to find the privilege `DELETE /v1/components/{id}` needs, and confirm that a delete privilege granted with a wildcard repository (`nx-repository-view-raw-*-delete`) also allows deleting from the raw hosted repository; restore any deleted component by re-fetching through the proxy or re-uploading the hosted file; delete the test role and user afterwards
- [x] 2.3 Write the README "Nexus permissions" section from those notes: the call-to-privilege table with the Nexus version it was checked on, the two roles (`nexus-cleanup-dry-run`, `nexus-cleanup-execute`) as `POST /service/rest/v1/security/roles` bodies and as UI steps with one user each, why delete privileges name repositories, the `--pattern` conflict, and what a missing privilege looks like; verify each role body by creating it on the reference instance with the documented request and running a dry run and a capped execute as its user

## 3. Separate credentials for the execute job

- [x] 3.1 README, in the permissions section: the edit per CI system that gives the execute job the execute user — GitLab `environment:` plus environment-scoped variables, Jenkins a second credential id in the execute stage, Forgejo differently named secrets in the execute step with its weaker isolation stated — and the warning that `init --force` rewrites the edit; verify each snippet against the matching file under `examples/<system>/` (the edited line exists there as quoted)


## 4. Upgrading a configuration repository

- [x] 4.1 Add `scaffold upgrade [dir]` to `scaffold.nu`: in whichever of the pipelines in `CI_SYSTEMS`, `configs/*.yaml`, `configs/*.yml` and the editor files in `EDITORS` exist, rewrite image pins under any registry (`nexus-cleanup` after `/`, a quote or whitespace, then `:` and a digit or `@sha256:`) to `VERSION` keeping `X.Y` or `X.Y.Z` precision, replace both digest forms by the tag with one stderr warning per line naming the file and line and advising to re-add a verified digest, rewrite `NEXUS_CLEANUP_VERSION: v<version>` and `nexus-cleanup/v<version>/schema/`, and copy `NU_VERSION` and `NU_SHA256` from the module's own Forgejo template only while the workflow's `asset=` line names `x86_64-unknown-linux-musl`, otherwise leaving them and saying so on stderr; write only changed files, list each on stderr, say so when nothing changed; verify with tests in `tests/test-scaffold.nu` over copies of every `examples/<system>/`, covering each spec scenario: pins at `0.0.1` and an older Forgejo Nushell come back byte for byte as the rendered example; the arm64 asset keeps `NU_VERSION` and `NU_SHA256` with a note; `nexus-cleanup:0.0` becomes the current `X.Y`; both digest forms become the current tag with one warning each; a mirror prefix is kept; the GitLab job names `nexus-cleanup:dry-run`, `nexus-cleanup:execute` and `.nexus-cleanup:` are unchanged; a file outside the list is untouched; a second run changes nothing
- [x] 4.2 Add `main upgrade` to the entrypoint with `scaffold upgrade-args` parsing by hand like `init` (one optional directory, `--help`, exit 2 for an unknown option, a run flag, a second directory or a filesystem error); verify with tests in `tests/test-cli.nu`: `upgrade` in an `init`-written directory pinned at an older version exits 0 and lists the changed files on stderr with stdout empty, `upgrade --execute` exits 2 and writes nothing, a missing directory exits 2, `upgrade --help` lists its usage, and `NEXUS_URL` unset or a placeholder does not matter
- [x] 4.3 README: an "Upgrading" section with `docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/bond-os/nexus-cleanup:X.Y.Z upgrade` between `x-release-please-start-version` / `-end` markers, followed by the rootless sentence from "Getting started" (`--userns=keep-id` for rootless Podman, `--user 0:0` for rootless Docker, linking "Who the container runs as"); before the command, that it supports tag pins only and replaces a digest pin by the tag with a warning, and how to re-add a verified digest (`docker buildx imagetools inspect`, `gh attestation verify`); that Forgejo's Nushell pins move with it unless the workflow uses the arm64 binary; the advice to read `CHANGELOG.md` and `git diff` first, `init --force` as the alternative, and a pointer to a Renovate regex manager over the image and schema patterns; `upgrade` in the CLI help and "Getting started"; make the "Pin an exact version, or a digest" paragraph link to this section; replace the inline bump advice in "Getting started", "Editor support" and "CI" with links to it; verify the marked block holds exactly one X.Y.Z, on the image line, and that `tests/test-examples.nu`'s release-marker checks still pass
- [x] 4.4 AGENTS.md: extend the `init` decisions to `upgrade` — its own argument parsing, exit 2 for every failure, a repository named `upgrade` reachable only through `--pattern` or a configuration file — and the Layout line for `scaffold.nu`; verify by reading the diff against design.md
- [x] 4.5 Build the image locally, run `.github/scripts/image-smoke.sh` against it, and run its `upgrade` with the README's command against a copy of `examples/forgejo/` pinned at `0.0.1`; verify the tree comes back as the example

## 5. Integration

- [x] 5.1 Run `nu tests/run-tests.nu` inside `ghcr.io/nushell/nushell:0.115.1-alpine` and verify it passes
- [x] 5.2 Run `openspec validate document-least-privilege-and-upgrades --strict` and verify it passes

## Workflow follow-up

- Commit the message change and the deletion handling as `fix:`, the `upgrade` subcommand as `feat:`, and the README sections as `docs:`.
- Archive the change after merge.
