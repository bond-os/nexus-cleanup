# Derives the scope a component belongs to: the distribution release or
# repository section that its versions should compete within.
#
# A repository can hold the same package name and architecture for several
# releases, and nothing in the component metadata says so — only the asset path
# does. Scope is therefore part of the retention key.
#
# The rule is per-format on purpose. A maven-style layout puts the version in
# the directory, so a blanket directory rule would give every version its own
# group and silently retain everything.

# Used when a format offers no dependable release or section signal.
export const IMPLICIT_SCOPE = "*"

def first-path [component: record]: nothing -> string {
    $component.assets? | default [] | each {|a| $a.path? | default "" } | where {|p| $p | is-not-empty } | get --optional 0 | default ""
}

# The scope named by a caller-supplied pattern, or the implicit scope when the
# path does not match.
def scope-from-pattern [component: record, pattern: string]: nothing -> string {
    let path = (first-path $component)
    if ($path | is-empty) { return $IMPLICIT_SCOPE }
    let m = ($path | parse --regex $pattern)
    if ($m | is-empty) { return $IMPLICIT_SCOPE }
    let scope = ($m | first | get --optional scope | default "")
    if ($scope | is-empty) { $IMPLICIT_SCOPE } else { $scope }
}

# yum: the asset's directory. Release trees, updates trees and distribution
# versions each live in their own directory, and none of them carries the
# component's own version.
def scope-yum [component: record]: nothing -> string {
    let path = (first-path $component)
    if ($path | is-empty) { return $IMPLICIT_SCOPE }
    let dir = ($path | path dirname)
    if ($dir | is-empty) { $IMPLICIT_SCOPE } else { $dir }
}

# apt: the suite the repository is configured to proxy. A Nexus apt proxy is
# pinned to one distribution, so this is constant per repository — carried so
# the report states which suite the repository represents.
def scope-apt [repository: record]: nothing -> string {
    let distribution = ($repository.distribution? | default "")
    if ($distribution | is-empty) { $IMPLICIT_SCOPE } else { $distribution }
}

# The scope of one component. `repository` optionally carries the repository's
# format-specific configuration, such as an apt distribution.
export def "scope of" [
    component: record
    repository: record = {}
    --pattern: string = ""
]: nothing -> string {
    if ($pattern | is-not-empty) { return (scope-from-pattern $component $pattern) }

    match ($component.format? | default "" | str lowercase) {
        "yum" => (scope-yum $component)
        "apt" => (scope-apt $repository)
        _ => $IMPLICIT_SCOPE
    }
}
