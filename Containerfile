# Pinned: Nushell breaks compatibility between minor releases, so the CI image
# and the developer floor move together and deliberately.
FROM ghcr.io/nushell/nushell:0.115.1-alpine

WORKDIR /work
COPY nexus-cleanup.nu /work/nexus-cleanup.nu
COPY nexus-cleanup /work/nexus-cleanup

# Dry run by default: the image inherits the tool's safe default, and --execute
# must be passed explicitly.
ENTRYPOINT ["nu", "/work/nexus-cleanup.nu"]
