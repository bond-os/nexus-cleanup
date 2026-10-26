#!/usr/bin/env bash
# Checks that the Forgejo template's NU_SHA256 is the checksum of the Nushell
# release asset its NU_VERSION installs. Renovate moves NU_VERSION but cannot
# compute the checksum, and the test suite never downloads anything, so without
# this a Nushell update would pass CI and break every generated Forgejo pipeline.
# Downloads from github.com; maintenance automation only, never part of the image.
#
#   .github/scripts/nushell-checksum.sh [TEMPLATE]
#
# TEMPLATE defaults to the Forgejo pipeline template. Its rendered copy under
# examples/forgejo/ is held equal to it by tests/test-examples.nu.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [TEMPLATE]" >&2
  exit 2
fi
template=${1:-nexus-cleanup/templates/ci/forgejo/.forgejo/workflows/nexus-cleanup.yml}

version=$(sed -nE 's/^[[:space:]]*NU_VERSION:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$template")
pinned=$(sed -nE 's/^[[:space:]]*NU_SHA256:[[:space:]]*([0-9a-f]{64})[[:space:]]*$/\1/p' "$template")
if [ -z "$version" ] || [ -z "$pinned" ]; then
  echo "could not read NU_VERSION and NU_SHA256 from $template" >&2
  exit 1
fi

# The same asset the template's "Install Nushell" step downloads.
asset="nu-${version}-x86_64-unknown-linux-musl"
url="https://github.com/nushell/nushell/releases/download/${version}/${asset}.tar.gz"
tarball=$(mktemp)
trap 'rm -f "$tarball"' EXIT
curl -fsSL --retry 3 -o "$tarball" "$url"

actual=$(sha256sum "$tarball" | cut -d ' ' -f 1)
if [ "$actual" != "$pinned" ]; then
  echo "NU_SHA256 in $template does not match Nushell $version" >&2
  echo "  pinned: $pinned" >&2
  echo "  actual: $actual" >&2
  echo "Set NU_SHA256 to the actual checksum in the template and in examples/forgejo/." >&2
  exit 1
fi
echo "Nushell $version: NU_SHA256 matches $asset.tar.gz"
