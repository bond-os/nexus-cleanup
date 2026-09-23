# Nexus 3 REST access: client record, retry, pagination, repository listing,
# component listing and component deletion.
#
# Every request goes through the client's `fetch` closure, so the risky parts —
# paging and retry classification — are testable without a network. The closure
# returns {status, body} and never the full response record: `http --full`
# carries the request's Authorization header, and nothing may hand that on.
#
# Nothing here reads or branches on the Nexus version. Support for older
# instances comes from tolerant parsing: unknown fields are ignored, documented
# fields may be absent, and paging follows the continuation token alone.

const RETRYABLE_STATUSES = [429 500 502 503 504]

# Formats whose repository configuration declares the scope of its components.
const SCOPE_CONFIG_FORMATS = ["apt"]

# The real fetch. Returns status and body only.
def http-fetch []: nothing -> closure {
    {|req|
        let response = if ($req.username | is-empty) {
            if $req.method == "DELETE" {
                http delete --full --allow-errors --max-time $req.timeout $req.url
            } else {
                http get --full --allow-errors --max-time $req.timeout $req.url
            }
        } else {
            if $req.method == "DELETE" {
                http delete --full --allow-errors --max-time $req.timeout --user $req.username --password $req.password $req.url
            } else {
                http get --full --allow-errors --max-time $req.timeout --user $req.username --password $req.password $req.url
            }
        }
        {status: $response.status, body: ($response.body? | default {})}
    }
}

# Build a client. Makes no request.
export def "api client" [
    base_url: string
    --username: string = ""
    --password: string = ""
    --timeout: duration = 30sec
    --max-attempts: int = 4
    --backoff: duration = 250ms
    --fetch: any = null
]: nothing -> record {
    {
        base_url: ($base_url | str trim --right --char "/")
        username: $username
        password: $password
        timeout: $timeout
        max_attempts: (if $max_attempts < 1 { 1 } else { $max_attempts })
        backoff: $backoff
        fetch: (if $fetch == null { http-fetch } else { $fetch })
    }
}

# Repository name patterns are globs, not regexes: `yum-*` should mean what an
# operator expects, and repository names routinely contain dots.
export def "api glob-to-regex" [pattern: string]: nothing -> string {
    let body = (
        $pattern
        | split chars
        | each {|c|
            if $c == "*" { ".*" } else if $c == "?" { "." } else if ($c =~ '^[A-Za-z0-9_-]$') { $c } else { "\\" + $c }
        }
        | str join
    )
    $"^($body)$"
}

def retryable [status: int]: nothing -> bool {
    $status in $RETRYABLE_STATUSES
}

# One request, retried on transport and retryable statuses with bounded
# exponential backoff. Raises with the final status and attempt count; the
# message never carries credentials.
def request [client: record, method: string, url: string, what: string] {
    mut attempt = 0
    mut last_status = 0
    mut last_message = ""

    while $attempt < $client.max_attempts {
        $attempt = $attempt + 1

        let outcome = (try {
            let r = (do $client.fetch {
                method: $method
                url: $url
                username: $client.username
                password: $client.password
                timeout: $client.timeout
            })
            {status: ($r.status? | default 0), body: ($r.body? | default {}), transport: ""}
        } catch {|e|
            {status: 0, body: {}, transport: ($e.msg? | default "transport failure")}
        })

        if ($outcome.transport | is-empty) and (not (retryable $outcome.status)) {
            return {status: $outcome.status, body: $outcome.body, attempts: $attempt}
        }

        $last_status = $outcome.status
        $last_message = $outcome.transport

        if $attempt < $client.max_attempts {
            let delay = ($client.backoff * ($attempt * $attempt))
            if $delay > 0ns { sleep $delay }
        }
    }

    let detail = if ($last_message | is-empty) { $"HTTP ($last_status)" } else { $last_message }
    error make {msg: $"($what) failed after ($attempt) attempt\(s\): ($detail)"}
}

def require-ok [response: record, what: string] {
    if $response.status >= 400 {
        error make {msg: $"($what) failed after ($response.attempts) attempt\(s\): HTTP ($response.status)"}
    }
}

# Repositories the instance exposes, with name, format and type.
export def "api repositories" [client: record]: nothing -> list<record> {
    let r = (request $client "GET" $"($client.base_url)/service/rest/v1/repositories" "listing repositories")
    require-ok $r "listing repositories"
    $r.body | default []
}

# Narrow a repository listing to the proxies the caller asked for. A named
# repository that is not a proxy is refused rather than silently skipped; a
# pattern simply excludes non-proxies.
export def "api select-proxies" [
    repositories: list<record>
    names: list<string>
    --pattern: string = ""
]: nothing -> list<record> {
    if ($names | is-not-empty) {
        # A `for` loop, not `each`: an error raised inside a closure is re-wrapped
        # as "Eval block failed", losing the message the operator needs.
        mut picked = []
        for n in $names {
            let hit = ($repositories | where name == $n | get --optional 0)
            if $hit == null {
                error make {msg: $"repository '($n)' does not exist on this instance"}
            }
            if $hit.type != "proxy" {
                error make {msg: $"repository '($n)' is a ($hit.type) repository, not a proxy; only proxy repositories can be cleaned"}
            }
            $picked = ($picked | append $hit)
        }
        return $picked
    }
    if ($pattern | is-not-empty) {
        let re = (api glob-to-regex $pattern)
        return ($repositories | where type == "proxy" | where {|r| $r.name =~ $re })
    }
    []
}

# The format-specific configuration a repository declares, when its format has
# one that bears on scope. An unreachable configuration is not fatal.
export def "api repository-config" [client: record, repository: record]: nothing -> record {
    let format = ($repository.format? | default "")
    if $format not-in $SCOPE_CONFIG_FORMATS { return {} }

    let url = $"($client.base_url)/service/rest/v1/repositories/($format)/proxy/($repository.name)"
    let outcome = (try { request $client "GET" $url "reading repository configuration" } catch {|e| null })
    if $outcome == null or $outcome.status >= 400 { return {} }
    $outcome.body | get --optional $format | default {}
}

# Every component of a repository, following continuation tokens to the end.
# A truncated enumeration raises: a partial set must never reach the policy.
export def "api components" [client: record, repository: string]: nothing -> list<record> {
    mut components = []
    mut token: any = null

    loop {
        let query = (
            if $token == null {
                {repository: $repository}
            } else {
                {repository: $repository, continuationToken: $token}
            } | url build-query
        )
        let url = $"($client.base_url)/service/rest/v1/components?($query)"
        let r = (request $client "GET" $url $"enumerating components of '($repository)'")
        require-ok $r $"enumerating components of '($repository)'"

        $components = ($components | append ($r.body.items? | default []))
        $token = ($r.body.continuationToken? | default null)
        if $token == null { break }
    }

    $components
}

# Delete one component. A failure is reported per component and does not abort
# the run; a component already gone counts as deleted.
export def "api delete-component" [client: record, id: string]: nothing -> record {
    let outcome = (try {
        request $client "DELETE" $"($client.base_url)/service/rest/v1/components/($id)" $"deleting component ($id)"
    } catch {|e|
        {status: 0, body: {}, attempts: $client.max_attempts, failure: ($e.msg? | default "request failed")}
    })

    if ($outcome.failure? | default "" | is-not-empty) {
        return {id: $id, deleted: false, note: "", error: $outcome.failure}
    }
    if $outcome.status == 404 {
        return {id: $id, deleted: true, note: "component was already absent", error: ""}
    }
    if $outcome.status >= 400 {
        let message = ($outcome.body.message? | default "")
        let detail = if ($message | is-empty) { "" } else { $": ($message)" }
        return {id: $id, deleted: false, note: "", error: $"HTTP ($outcome.status)($detail)"}
    }
    {id: $id, deleted: true, note: "", error: ""}
}
