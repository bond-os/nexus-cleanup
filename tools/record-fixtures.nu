#!/usr/bin/env nu
# Records redacted Nexus API responses into tests/fixtures/.
#
# Development-time only: the shipped module never reads this file and the CI
# image does not need it. Re-run it against an upgraded Nexus and read the diff
# when a response shape changes.
#
#   NEXUS_URL / NEXUS_USERNAME / NEXUS_PASSWORD must be set.
#   nu tools/record-fixtures.nu [repo ...] [--out tests/fixtures] [--max-pages N]

export const PLACEHOLDER_HOST = "nexus.example.invalid"

# Fields replaced wholesale, whatever their value or depth.
export const IDENTITY_FIELDS = {
    uploader: "redacted-user"
    uploaderIp: "0.0.0.0"
    blobStoreName: "redacted-blobstore"
    # blobRef embeds the blob store name and a store UUID: "proxies@<uuid>@<ts>".
    blobRef: "redacted-blobref"
}

# Fields that change on their own between runs and that the tool never reads.
# Normalised so a re-record produces a readable diff instead of pure churn.
export const VOLATILE_FIELDS = {
    size: 0
    lastDownloaded: null
    lastVerified: null
}

# A secret shorter than this is not substituted: too likely to appear inside
# unrelated words and corrupt the fixture.
const MIN_SECRET_LEN = 3

# Replace identity-bearing fields and every occurrence of the instance's hosts
# and secrets, at any depth, in any record, list or string.
export def redact [
    value: any
    --hosts: list<string> = []
    --secrets: list<string> = []
]: nothing -> any {
    let kind = ($value | describe --detailed | get type)

    if $kind == "record" {
        $value
        | items {|k, v|
            let identity = ($IDENTITY_FIELDS | get --optional $k)
            let new = if $identity != null {
                $identity
            } else if $k in ($VOLATILE_FIELDS | columns) {
                $VOLATILE_FIELDS | get $k
            } else {
                redact $v --hosts $hosts --secrets $secrets
            }
            {k: $k, v: $new}
        }
        | reduce --fold {} {|it, acc| $acc | insert $it.k $it.v }
    } else if $kind == "list" {
        $value | each {|v| redact $v --hosts $hosts --secrets $secrets }
    } else if $kind == "string" {
        mut s = $value
        # Longest first, so "host:port" is replaced before the bare host.
        for h in ($hosts | where {|h| ($h | str length) > 0 } | sort-by {|h| $h | str length } --reverse) {
            $s = ($s | str replace --all $h $PLACEHOLDER_HOST)
        }
        for x in ($secrets | where {|x| ($x | str length) >= $MIN_SECRET_LEN }) {
            $s = ($s | str replace --all $x "REDACTED")
        }
        $s
    } else {
        $value
    }
}

# The host forms worth substituting, derived from a base URL.
export def hosts-of [base_url: string]: nothing -> list<string> {
    let parsed = ($base_url | url parse)
    let host = ($parsed.host? | default "")
    let port = ($parsed.port? | default "")
    if ($host | is-empty) { return [] }
    if ($port | is-empty) { [$host] } else { [$"($host):($port)", $host] }
}

def fetch [url: string, user: string, password: string]: nothing -> record {
    if ($user | is-empty) {
        http get --full --allow-errors --max-time 60sec $url
    } else {
        http get --full --allow-errors --max-time 60sec --user $user --password $password $url
    }
}

def require-ok [response: record, what: string] {
    if $response.status != 200 {
        print --stderr $"record-fixtures: ($what) returned HTTP ($response.status)"
        exit 3
    }
}

def main [
    ...repositories: string            # repositories to record; default: every proxy
    --out: string = "tests/fixtures"   # directory to write fixtures into
    --max-pages: int = 0               # 0 = every page
] {
    let base = ($env.NEXUS_URL? | default "" | str trim --right --char "/")
    if ($base | is-empty) {
        print --stderr "record-fixtures: NEXUS_URL is not set"
        exit 2
    }
    let user = ($env.NEXUS_USERNAME? | default "")
    let password = ($env.NEXUS_PASSWORD? | default "")
    let hosts = (hosts-of $base)
    let secrets = ([$user $password] | where {|s| ($s | is-not-empty) })

    mkdir $out

    print --stderr $"record-fixtures: reading repositories from ($base)"
    let repos = (fetch $"($base)/service/rest/v1/repositories" $user $password)
    require-ok $repos "GET /service/rest/v1/repositories"

    let all = $repos.body
    (redact $all --hosts $hosts --secrets $secrets
        | to json --indent 2
        | save --force $"($out)/repositories.json")
    print --stderr $"  wrote ($out)/repositories.json — ($all | length) repositories"

    let selected = if ($repositories | is-empty) {
        $all | where type == "proxy"
    } else {
        $all | where name in $repositories
    }

    if ($selected | is-empty) {
        print --stderr "record-fixtures: no repositories selected"
        exit 2
    }

    for repo in $selected {
        mkdir $"($out)/($repo.format)"
        mut token: any = null
        mut page = 0
        mut total = 0

        loop {
            let query = if $token == null {
                {repository: $repo.name} | url build-query
            } else {
                {repository: $repo.name, continuationToken: $token} | url build-query
            }
            let response = (fetch $"($base)/service/rest/v1/components?($query)" $user $password)
            require-ok $response $"GET components for ($repo.name)"

            let body = $response.body
            let path = $"($out)/($repo.format)/($repo.name)-page-($page).json"
            (redact $body --hosts $hosts --secrets $secrets
                | to json --indent 2
                | save --force $path)

            $total = $total + ($body.items | length)
            $page = $page + 1
            $token = ($body.continuationToken? | default null)
            if $token == null { break }
            if $max_pages > 0 and $page >= $max_pages { break }
        }

        print --stderr $"  wrote ($repo.format)/($repo.name) — ($page) page\(s), ($total) components"
    }

    print --stderr "record-fixtures: done"
}
