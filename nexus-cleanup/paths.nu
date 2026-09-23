# Path-derived retention: a caller-supplied pattern assigns the grouping name and
# the version of every component whose asset path it matches.
#
# The pattern is the whole rule. A component it does not match is never a
# deletion candidate — the policy decides it before grouping, so no keep count or
# ordering outcome can ever reach it.

def first-path [component: record]: nothing -> string {
    $component.assets? | default [] | each {|a| $a.path? | default "" } | where {|p| $p | is-not-empty } | get --optional 0 | default ""
}

# {name, version} extracted from the component's asset path, or null when the
# path does not match or yields an empty name or version.
export def "path match" [component: record, pattern: string]: nothing -> any {
    let path = (first-path $component)
    if ($path | is-empty) { return null }
    let m = ($path | parse --regex $pattern)
    if ($m | is-empty) { return null }
    let name = ($m | first | get --optional name | default "")
    let version = ($m | first | get --optional version | default "")
    if ($name | is-empty) or ($version | is-empty) { return null }
    {name: $name, version: $version}
}
