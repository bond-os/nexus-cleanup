# Version comparators. Each scheme has a parse predicate and a comparator; the
# policy layer uses the predicate to decide whether a group is orderable at all,
# so a comparator is never asked to guess at a string it cannot read.

export const SCHEMES = ["generic", "debian", "rpm", "date"]

# semver-ish: optional leading v, dotted numeric core, optional pre-release,
# optional build metadata (which is ignored entirely when ordering).
const GENERIC_RE = '^v?(?P<core>\d+(?:\.\d+)*)(?:-(?P<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+(?P<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$'

def cmp-num [a: int, b: int]: nothing -> int {
    if $a < $b { -1 } else if $a > $b { 1 } else { 0 }
}

def cmp-str [a: string, b: string]: nothing -> int {
    if $a < $b { -1 } else if $a > $b { 1 } else { 0 }
}

def generic-parse [v: string]: nothing -> any {
    let m = ($v | parse --regex $GENERIC_RE)
    if ($m | is-empty) { return null }
    let r = ($m | first)
    {
        core: ($r.core | split row "." | each {|s| $s | into int })
        pre: (if ($r.pre | is-empty) { [] } else { $r.pre | split row "." })
    }
}

def cmp-core [a: list<int>, b: list<int>]: nothing -> int {
    let n = ([($a | length) ($b | length)] | math max)
    mut out = 0
    for i in 0..<$n {
        if $out == 0 {
            let x = ($a | get --optional $i | default 0)
            let y = ($b | get --optional $i | default 0)
            $out = (cmp-num $x $y)
        }
    }
    $out
}

def cmp-pre [a: list<string>, b: list<string>]: nothing -> int {
    # A release outranks any pre-release of the same core.
    if (($a | is-empty) and ($b | is-empty)) { return 0 }
    if ($a | is-empty) { return 1 }
    if ($b | is-empty) { return (-1) }

    let n = ([($a | length) ($b | length)] | math min)
    mut out = 0
    for i in 0..<$n {
        if $out == 0 {
            let x = ($a | get $i)
            let y = ($b | get $i)
            let x_num = ($x =~ '^\d+$')
            let y_num = ($y =~ '^\d+$')
            $out = if ($x_num and $y_num) {
                cmp-num ($x | into int) ($y | into int)
            } else if $x_num {
                -1  # a numeric identifier ranks below an alphanumeric one
            } else if $y_num {
                1
            } else {
                cmp-str $x $y
            }
        }
    }
    if $out != 0 { return $out }
    # All shared identifiers equal: the shorter pre-release ranks lower.
    cmp-num ($a | length) ($b | length)
}

def generic-compare [a: string, b: string]: nothing -> int {
    let pa = (generic-parse $a)
    let pb = (generic-parse $b)
    if $pa == null { error make {msg: $"not a generic version: '($a)'"} }
    if $pb == null { error make {msg: $"not a generic version: '($b)'"} }

    let core = (cmp-core $pa.core $pb.core)
    if $core != 0 { return $core }
    cmp-pre $pa.pre $pb.pre
}

# --- debian (dpkg) --------------------------------------------------------
#
# [epoch:]upstream[-revision]; epoch numeric, then upstream and revision each
# compared by dpkg's alternating non-digit/digit run algorithm.

const DEBIAN_RE = '^(?:(?P<epoch>\d+):)?(?P<rest>[0-9][A-Za-z0-9.+~-]*)$'

def debian-parse [v: string]: nothing -> any {
    let m = ($v | parse --regex $DEBIAN_RE)
    if ($m | is-empty) { return null }
    let r = ($m | first)
    let parts = ($r.rest | split row "-")
    let has_revision = (($parts | length) > 1)
    {
        epoch: (if ($r.epoch | is-empty) { 0 } else { $r.epoch | into int })
        upstream: (if $has_revision { $parts | drop 1 | str join "-" } else { $r.rest })
        revision: (if $has_revision { $parts | last } else { "" })
    }
}

# dpkg's character order: `~` sorts before end-of-string, which sorts before
# letters, which sort before every other character.
def debian-char-rank [c: string]: nothing -> int {
    if $c == "~" { 0 } else if $c == "" { 1 } else if ($c =~ '^[A-Za-z]$') { 2 } else { 3 }
}

def debian-cmp-nondigit [a: string, b: string]: nothing -> int {
    let xs = ($a | split chars)
    let ys = ($b | split chars)
    let n = ([($xs | length) ($ys | length)] | math max)
    mut out = 0
    for i in 0..<$n {
        if $out == 0 {
            let x = ($xs | get --optional $i | default "")
            let y = ($ys | get --optional $i | default "")
            let rx = (debian-char-rank $x)
            let ry = (debian-char-rank $y)
            $out = (if $rx != $ry { cmp-num $rx $ry } else { cmp-str $x $y })
        }
    }
    $out
}

def split-at-digit [s: string]: nothing -> record {
    let m = ($s | parse --regex '^(?P<head>[^0-9]*)(?P<tail>[0-9].*)?$' | first)
    {head: $m.head, tail: ($m.tail | default "")}
}

def split-at-nondigit [s: string]: nothing -> record {
    let m = ($s | parse --regex '^(?P<head>[0-9]*)(?P<tail>[^0-9].*)?$' | first)
    {head: $m.head, tail: ($m.tail | default "")}
}

def debian-compare-part [a: string, b: string]: nothing -> int {
    mut x = $a
    mut y = $b
    mut out = 0
    mut guard = 0
    while ($out == 0) and ((($x | is-not-empty) or ($y | is-not-empty)) and ($guard < 1000)) {
        $guard = $guard + 1
        let sx = (split-at-digit $x)
        let sy = (split-at-digit $y)
        $out = (debian-cmp-nondigit $sx.head $sy.head)
        if $out == 0 {
            let dx = (split-at-nondigit $sx.tail)
            let dy = (split-at-nondigit $sy.tail)
            let nx = (if ($dx.head | is-empty) { 0 } else { $dx.head | into int })
            let ny = (if ($dy.head | is-empty) { 0 } else { $dy.head | into int })
            $out = (cmp-num $nx $ny)
            $x = $dx.tail
            $y = $dy.tail
        }
    }
    $out
}

def debian-compare [a: string, b: string]: nothing -> int {
    let pa = (debian-parse $a)
    let pb = (debian-parse $b)
    if $pa == null { error make {msg: $"not a debian version: '($a)'"} }
    if $pb == null { error make {msg: $"not a debian version: '($b)'"} }

    let epoch = (cmp-num $pa.epoch $pb.epoch)
    if $epoch != 0 { return $epoch }
    let upstream = (debian-compare-part $pa.upstream $pb.upstream)
    if $upstream != 0 { return $upstream }
    debian-compare-part $pa.revision $pb.revision
}

# --- rpm (rpmvercmp) ------------------------------------------------------
#
# [epoch:]version[-release]; each of version and release compared by rpmvercmp:
# alternating alphabetic and numeric segments, every other character a
# separator, `~` sorting before everything and `^` after the base version but
# below the next release.

const RPM_RE = '^(?:(?P<epoch>\d+):)?(?P<version>[A-Za-z0-9][A-Za-z0-9._+~^]*)(?:-(?P<release>[A-Za-z0-9][A-Za-z0-9._+~^]*))?$'

def rpm-parse [v: string]: nothing -> any {
    let m = ($v | parse --regex $RPM_RE)
    if ($m | is-empty) { return null }
    let r = ($m | first)
    {
        epoch: (if ($r.epoch | is-empty) { 0 } else { $r.epoch | into int })
        version: $r.version
        release: ($r.release | default "")
    }
}

def rpm-significant [c: string]: nothing -> bool {
    ($c =~ '^[A-Za-z0-9]$') or ($c == "~") or ($c == "^")
}

def rpm-compare-part [a: string, b: string]: nothing -> int {
    let xs = ($a | split chars)
    let ys = ($b | split chars)
    let nx = ($xs | length)
    let ny = ($ys | length)
    mut i = 0
    mut j = 0
    mut res: any = null
    mut guard = 0

    while ($res == null) and ($guard < 10000) {
        $guard = $guard + 1

        # Skip separators.
        while ($i < $nx) and (not (rpm-significant ($xs | get $i))) { $i = $i + 1 }
        while ($j < $ny) and (not (rpm-significant ($ys | get $j))) { $j = $j + 1 }

        let cx = ($xs | get --optional $i | default "")
        let cy = ($ys | get --optional $j | default "")

        if ($cx == "~") or ($cy == "~") {
            # `~` sorts before everything, including the end of the string.
            if $cx != "~" { $res = 1 } else if $cy != "~" { $res = (-1) } else {
                $i = $i + 1
                $j = $j + 1
            }
            continue
        }

        if ($cx == "^") or ($cy == "^") {
            # `^` sorts after the end of the string but before anything else.
            if $cx == "" { $res = (-1) } else if $cy == "" { $res = 1 } else if $cx != "^" {
                $res = 1
            } else if $cy != "^" {
                $res = (-1)
            } else {
                $i = $i + 1
                $j = $j + 1
            }
            continue
        }

        if ($cx == "") or ($cy == "") { break }

        let numeric = ($cx =~ '^[0-9]$')
        let pattern = (if $numeric { '^[0-9]$' } else { '^[A-Za-z]$' })
        mut i2 = $i
        mut j2 = $j
        while ($i2 < $nx) and (($xs | get $i2) =~ $pattern) { $i2 = $i2 + 1 }
        while ($j2 < $ny) and (($ys | get $j2) =~ $pattern) { $j2 = $j2 + 1 }

        if $j2 == $j {
            # Segments are of different kinds: a numeric segment outranks an
            # alphabetic one.
            $res = (if $numeric { 1 } else { -1 })
            continue
        }

        let sx = ($xs | skip $i | take ($i2 - $i) | str join)
        let sy = ($ys | skip $j | take ($j2 - $j) | str join)
        let tx = (if $numeric { $sx | str trim --left --char '0' } else { $sx })
        let ty = (if $numeric { $sy | str trim --left --char '0' } else { $sy })

        if $numeric and (($tx | str length) != ($ty | str length)) {
            $res = (cmp-num ($tx | str length) ($ty | str length))
            continue
        }

        let c = (cmp-str $tx $ty)
        if $c != 0 {
            $res = $c
            continue
        }

        $i = $i2
        $j = $j2
    }

    if $res != null { return $res }
    let x_done = ($i >= $nx)
    let y_done = ($j >= $ny)
    if $x_done and $y_done { 0 } else if $x_done { -1 } else { 1 }
}

def rpm-compare [a: string, b: string]: nothing -> int {
    let pa = (rpm-parse $a)
    let pb = (rpm-parse $b)
    if $pa == null { error make {msg: $"not an rpm version: '($a)'"} }
    if $pb == null { error make {msg: $"not an rpm version: '($b)'"} }

    let epoch = (cmp-num $pa.epoch $pb.epoch)
    if $epoch != 0 { return $epoch }
    let version = (rpm-compare-part $pa.version $pb.version)
    if $version != 0 { return $version }
    rpm-compare-part $pa.release $pb.release
}

# --- date -----------------------------------------------------------------
#
# YYYYMMDD, a real calendar date, optionally followed by a suffix that does not
# begin with a digit (a same-day respin: 20250103-hotfix, 20250103hotfix).
# Ordered by date; within a day the bare date first, then respins in natural
# order. Never chosen by default — only by an explicit --version-scheme date.

const DATE_RE = '^(?P<date>[0-9]{8})(?P<suffix>(?:[^0-9].*)?)$'

def date-parse [v: string]: nothing -> any {
    let m = ($v | parse --regex $DATE_RE)
    if ($m | is-empty) { return null }
    let r = ($m | first)
    # Rejects impossible dates (20250229, 20251399) and accepts leap days.
    let real = (try { $r.date | into datetime --format "%Y%m%d" | ignore; true } catch { false })
    if not $real { return null }
    {date: ($r.date | into int), suffix: ($r.suffix | default "")}
}

# Natural order: digit runs compare numerically, other text by code point, and
# a shorter run list ranks lower when every shared run is equal.
def natural-compare [a: string, b: string]: nothing -> int {
    let xs = ($a | parse --regex '(?P<run>[0-9]+|[^0-9]+)' | get run)
    let ys = ($b | parse --regex '(?P<run>[0-9]+|[^0-9]+)' | get run)
    let n = ([($xs | length) ($ys | length)] | math min)
    mut out = 0
    for i in 0..<$n {
        if $out == 0 {
            let x = ($xs | get $i)
            let y = ($ys | get $i)
            $out = if ($x =~ '^[0-9]+$') and ($y =~ '^[0-9]+$') {
                cmp-num ($x | into int) ($y | into int)
            } else {
                cmp-str $x $y
            }
        }
    }
    if $out != 0 { return $out }
    cmp-num ($xs | length) ($ys | length)
}

def date-compare [a: string, b: string]: nothing -> int {
    let pa = (date-parse $a)
    let pb = (date-parse $b)
    if $pa == null { error make {msg: $"not a date version: '($a)'"} }
    if $pb == null { error make {msg: $"not a date version: '($b)'"} }

    let date = (cmp-num $pa.date $pb.date)
    if $date != 0 { return $date }
    # The bare date ranks below every same-day respin.
    if ($pa.suffix | is-empty) and ($pb.suffix | is-empty) { return 0 }
    if ($pa.suffix | is-empty) { return (-1) }
    if ($pb.suffix | is-empty) { return 1 }
    natural-compare $pa.suffix $pb.suffix
}

# Is this version string parseable under the given scheme?
export def "version parseable" [scheme: string, version: string]: nothing -> bool {
    match $scheme {
        "generic" => ((generic-parse $version) != null)
        "debian" => ((debian-parse $version) != null)
        "rpm" => ((rpm-parse $version) != null)
        "date" => ((date-parse $version) != null)
        _ => (error make {msg: $"unknown version scheme '($scheme)'"})
    }
}

# Compare two versions under the given scheme: -1 (a<b), 0 (equal), 1 (a>b).
# Raises on a version the scheme cannot parse — the caller checks first.
export def "version compare" [scheme: string, a: string, b: string]: nothing -> int {
    match $scheme {
        "generic" => (generic-compare $a $b)
        "debian" => (debian-compare $a $b)
        "rpm" => (rpm-compare $a $b)
        "date" => (date-compare $a $b)
        _ => (error make {msg: $"unknown version scheme '($scheme)'"})
    }
}

# Which comparator a repository format uses, unless the caller overrides it.
# Formats with no ecosystem rule of their own fall back to `generic`.
export def "version scheme-for-format" [format: string, override?: string]: nothing -> string {
    if ($override | is-not-empty) {
        if $override not-in $SCHEMES {
            error make {msg: $"unknown version scheme '($override)'; expected one of ($SCHEMES | str join ', ')"}
        }
        return $override
    }
    match ($format | str lowercase) {
        "apt" => "debian"
        "yum" => "rpm"
        _ => "generic"
    }
}
