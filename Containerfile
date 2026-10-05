# Pinned: Nushell breaks compatibility between minor releases, so the CI image
# and the developer floor move together and deliberately.
FROM ghcr.io/nushell/nushell:0.115.1-alpine

# Set by the build from nexus-cleanup/version.nu; the release job checks that it
# equals the release being published.
ARG VERSION=0.0.0

LABEL org.opencontainers.image.title="nexus-cleanup" \
      org.opencontainers.image.description="Deletes obsolete component versions from Nexus 3 proxy repositories" \
      org.opencontainers.image.source="https://github.com/bond-os/nexus-cleanup" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}"

# COPY only, never RUN: without a RUN step every platform builds without
# emulation. The tool lives outside the working directory so that a CI workspace
# mounted at /work cannot hide it.
COPY nexus-cleanup.nu /opt/nexus-cleanup/nexus-cleanup.nu
COPY nexus-cleanup /opt/nexus-cleanup/nexus-cleanup
COPY --chmod=0755 packaging/nexus-cleanup /usr/local/bin/nexus-cleanup

# The base image's `nushell` user, declared here rather than inherited so that
# upstream cannot change it, and numeric because Kubernetes cannot verify that
# a named user is non-root: `runAsNonRoot` would refuse to start the pod. The
# tool runs under any UID the runtime assigns instead. Set before WORKDIR, which
# creates /work owned by it.
USER 1000:1000

# Empty: relative output paths such as --summary-out land in whatever the CI
# system mounts here.
WORKDIR /work

# Dry run by default: the image inherits the tool's safe default, sets no
# environment and no default argument, and --execute must be passed explicitly.
ENTRYPOINT ["/usr/local/bin/nexus-cleanup"]
