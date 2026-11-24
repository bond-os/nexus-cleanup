#!/bin/sh
# Repairs the Forgejo template and generated example after Renovate moves
# NU_VERSION. Executed only by the trusted workflow from the default branch;
# TEMPLATE and EXAMPLE are untrusted pull-request data.
#
#   .github/scripts/repair-nushell-checksum.sh [TEMPLATE EXAMPLE]
#
# CURL_BIN and SHA256SUM_BIN are overridable for hermetic tests.
set -eu

if [ "$#" -ne 0 ] && [ "$#" -ne 2 ]; then
  echo "usage: $0 [TEMPLATE EXAMPLE]" >&2
  exit 2
fi

template=${1:-nexus-cleanup/templates/ci/forgejo/.forgejo/workflows/nexus-cleanup.yml}
example=${2:-examples/forgejo/.forgejo/workflows/nexus-cleanup.yml}
curl_bin=${CURL_BIN:-curl}
sha256sum_bin=${SHA256SUM_BIN:-sha256sum}

for file in "$template" "$example"; do
  if [ -L "$file" ] || [ ! -f "$file" ]; then
    echo "refusing non-regular file: $file" >&2
    exit 1
  fi
done

read_pin() {
  file=$1
  name=$2
  pattern=$3

  lines=$(grep -Ec "^[[:space:]]*${name}:" "$file" || true)
  if [ "$lines" -ne 1 ]; then
    echo "expected exactly one $name line in $file; found $lines" >&2
    return 1
  fi
  count=$(grep -Ec "^[[:space:]]*${name}:[[:space:]]*${pattern}[[:space:]]*$" "$file" || true)
  if [ "$count" -ne 1 ]; then
    echo "expected exactly one valid $name in $file; found $count" >&2
    return 1
  fi

  value=$(sed -nE "s/^[[:space:]]*${name}:[[:space:]]*(${pattern})[[:space:]]*$/\\1/p" "$file")
  if [ -z "$value" ]; then
    echo "could not read $name from $file" >&2
    return 1
  fi
  printf '%s' "$value"
}

version_pattern='[0-9]+\.[0-9]+\.[0-9]+'
checksum_pattern='[0-9a-f]{64}'
template_version=$(read_pin "$template" NU_VERSION "$version_pattern")
example_version=$(read_pin "$example" NU_VERSION "$version_pattern")
template_checksum=$(read_pin "$template" NU_SHA256 "$checksum_pattern")
example_checksum=$(read_pin "$example" NU_SHA256 "$checksum_pattern")

if [ "$template_version" != "$example_version" ]; then
  echo "NU_VERSION differs between $template and $example" >&2
  exit 1
fi
if [ "$template_checksum" != "$example_checksum" ]; then
  echo "NU_SHA256 differs between $template and $example" >&2
  exit 1
fi

asset="nu-${template_version}-x86_64-unknown-linux-musl"
url="https://github.com/nushell/nushell/releases/download/${template_version}/${asset}.tar.gz"
tarball=$(mktemp)
trap 'rm -f "$tarball"' EXIT
"$curl_bin" -fsSL --retry 3 -o "$tarball" "$url"
actual=$("$sha256sum_bin" "$tarball" | cut -d ' ' -f 1)

if ! printf '%s\n' "$actual" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "download checksum did not produce a SHA-256: $actual" >&2
  exit 1
fi
if [ "$actual" = "$template_checksum" ]; then
  echo "Nushell $template_version: NU_SHA256 already matches $asset.tar.gz"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -f "$tarball"; rm -rf "$work"' EXIT
sed -E "s/^([[:space:]]*NU_SHA256:[[:space:]]*)[0-9a-f]{64}([[:space:]]*)$/\\1${actual}\\2/" \
  "$template" > "$work/template"
sed -E "s/^([[:space:]]*NU_SHA256:[[:space:]]*)[0-9a-f]{64}([[:space:]]*)$/\\1${actual}\\2/" \
  "$example" > "$work/example"

if [ "$(grep -Ec "^[[:space:]]*NU_SHA256:[[:space:]]*${actual}[[:space:]]*$" "$work/template")" -ne 1 ] ||
  [ "$(grep -Ec "^[[:space:]]*NU_SHA256:[[:space:]]*${actual}[[:space:]]*$" "$work/example")" -ne 1 ]; then
  echo "refusing to write: replacement did not produce exactly one checksum in each file" >&2
  exit 1
fi

cat "$work/template" > "$template"
cat "$work/example" > "$example"
echo "Repaired NU_SHA256 for Nushell $template_version: $actual"
