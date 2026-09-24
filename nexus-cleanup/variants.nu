# Derives the architecture/variant key of a component, using a per-format
# adapter. Each adapter tries, in order: the source Nexus actually populates for
# that format, then the asset filename, then the implicit variant. Nothing is
# guessed for a format with no architecture dimension — a directory named
# `x86_64` in a raw repository must not split that repository into groups.

# Used when a format carries no architecture dimension, or when the architecture
# cannot be determined. Reported as-is so "no split was applied here" is visible.
export const IMPLICIT_VARIANT = "*"

# Used when a component explicitly covers every architecture at once — a docker
# manifest list or an OCI image index. Deliberately not "all": in Debian `all` is
# a real architecture value for arch-independent packages.
export const MULTIARCH_VARIANT = "multiarch"

# Content types whose asset is an index over per-architecture manifests.
const MULTIARCH_CONTENT_TYPES = [
    "application/vnd.docker.distribution.manifest.list.v2+json"
    "application/vnd.oci.image.index.v1+json"
]

# Debian package filename: <name>_<version>_<arch>.deb
const DEB_ARCH_RE = '_(?P<arch>[A-Za-z0-9][A-Za-z0-9-]*)\.deb$'

# RPM package filename: <name>-<version>-<release>.<arch>.rpm
const RPM_ARCH_RE = '\.(?P<arch>[A-Za-z0-9_]+)\.rpm$'

def paths-of [component: record]: nothing -> list<string> {
    $component.assets? | default [] | each {|a| $a.path? | default "" }
}

def arch-from-paths [component: record, pattern: string]: nothing -> list<string> {
    paths-of $component
    | each {|p| $p | parse --regex $pattern | get arch }
    | flatten
    | uniq
}

# apt and yum both carry the architecture in the component's `group` field, with
# the asset filename as the fallback for instances that do not populate it.
def variant-from-group [component: record, filename_pattern: string]: nothing -> list<string> {
    let group = ($component.group? | default "")
    if ($group | is-not-empty) { return [$group] }
    let from_path = (arch-from-paths $component $filename_pattern)
    if ($from_path | is-not-empty) { return $from_path }
    [$IMPLICIT_VARIANT]
}

# docker: the architecture is on the asset attribute for a single-architecture
# manifest, and absent for an index — which covers every architecture rather
# than none.
def variant-docker [component: record]: nothing -> list<string> {
    let variants = (
        $component.assets?
        | default []
        | each {|a|
            let arch = ($a.docker?.architecture? | default "")
            if ($arch | is-not-empty) {
                $arch
            } else if (($a.contentType? | default "") in $MULTIARCH_CONTENT_TYPES) {
                $MULTIARCH_VARIANT
            } else {
                $IMPLICIT_VARIANT
            }
        }
        | uniq
    )
    if ($variants | is-empty) { [$IMPLICIT_VARIANT] } else { $variants }
}

# Every variant a component carries. Never empty: falls back to IMPLICIT_VARIANT.
export def "variant of" [component: record]: nothing -> list<string> {
    match ($component.format? | default "" | str lowercase) {
        "apt" => (variant-from-group $component $DEB_ARCH_RE)
        "yum" => (variant-from-group $component $RPM_ARCH_RE)
        "docker" => (variant-docker $component)
        _ => [$IMPLICIT_VARIANT]
    }
}
