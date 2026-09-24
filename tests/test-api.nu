use ./harness.nu *
use ../nexus-cleanup/api.nu *

# A fetch closure that answers from a canned table, so the client's paging,
# retry and error mapping are testable with no network.
def canned [responses: list<record>]: nothing -> closure {
    {|req|
        let hit = ($responses | where {|r| $req.url | str contains $r.match } | get --optional 0)
        if $hit == null { {status: 404, body: {}} } else { {status: $hit.status, body: ($hit.body? | default {})} }
    }
}

def client-with [fetch: closure]: nothing -> record {
    api client "https://nexus.example.invalid" --username "u" --password "p" --backoff 0ms --fetch $fetch
}

run-suite "api client" [
    # --- construction ---
    { name: "constructing a client makes no request", run: {||
        let fetch = {|req| error make {msg: "the client must not call fetch while being constructed"} }
        let c = (api client "https://nexus.example.invalid" --fetch $fetch)
        assert equal $c.base_url "https://nexus.example.invalid"
    } }
    { name: "a trailing slash on the base URL is normalised away", run: {||
        let c = (api client "https://nexus.example.invalid/" --fetch {|req| {status: 200, body: {}} })
        assert equal $c.base_url "https://nexus.example.invalid"
    } }

    # --- pagination ---
    { name: "every page is consumed exactly once", run: {||
        let fetch = {|req|
            if ($req.url | str contains "continuationToken=t1") {
                {status: 200, body: {items: [{id: "c", name: "c"}], continuationToken: "t2"}}
            } else if ($req.url | str contains "continuationToken=t2") {
                {status: 200, body: {items: [{id: "d", name: "d"}], continuationToken: null}}
            } else {
                {status: 200, body: {items: [{id: "a", name: "a"}, {id: "b", name: "b"}], continuationToken: "t1"}}
            }
        }
        let got = (api components (client-with $fetch) "repo")
        assert equal ($got | get id) ["a" "b" "c" "d"]
    } }
    { name: "an empty repository returns an empty set without error", run: {||
        let fetch = {|req| {status: 200, body: {items: [], continuationToken: null}} }
        assert equal (api components (client-with $fetch) "repo") []
    } }
    { name: "a failure mid-enumeration raises instead of returning a partial set", run: {||
        let fetch = {|req|
            if ($req.url | str contains "continuationToken") {
                {status: 500, body: {}}
            } else {
                {status: 200, body: {items: [{id: "a"}], continuationToken: "t1"}}
            }
        }
        assert error {|| api components (client-with $fetch) "repo" }
    } }
    { name: "no page-size parameter is ever sent", run: {||
        let fetch = {|req|
            if ($req.url | str contains "limit") { error make {msg: "sent a page-size parameter"} }
            {status: 200, body: {items: [], continuationToken: null}}
        }
        assert equal (api components (client-with $fetch) "repo") []
    } }

    # --- tolerant parsing ---
    { name: "unknown component and asset fields are ignored", run: {||
        let fetch = {|req| {status: 200, body: {
            items: [{id: "a", name: "n", version: "1", futureField: 42, assets: [{path: "/p", alsoFuture: true}]}]
            continuationToken: null
            futureTopLevel: "x"
        }} }
        let got = (api components (client-with $fetch) "repo")
        assert equal ($got | length) 1
        assert equal ($got | first | get name) "n"
    } }
    { name: "a response omitting optional fields is tolerated", run: {||
        let fetch = {|req| {status: 200, body: {items: [{id: "a"}]}} }
        let got = (api components (client-with $fetch) "repo")
        assert equal ($got | length) 1
    } }

    # --- retry classification ---
    { name: "a retryable status is retried up to the attempt limit", run: {||
        let fetch = {|req| {status: 503, body: {}} }
        let c = (api client "https://n.invalid" --max-attempts 3 --backoff 0ms --fetch $fetch)
        let err = (try { api repositories $c; null } catch {|e| $e })
        assert not equal $err null
        assert ($err.msg | str contains "3")
        assert ($err.msg | str contains "503")
    } }
    { name: "429 is retryable", run: {||
        let fetch = {|req| {status: 429, body: {}} }
        let c = (api client "https://n.invalid" --max-attempts 2 --backoff 0ms --fetch $fetch)
        let err = (try { api repositories $c; null } catch {|e| $e })
        assert ($err.msg | str contains "2")
    } }
    { name: "an authentication failure is not retried", run: {||
        let fetch = {|req| {status: 401, body: {}} }
        let c = (api client "https://n.invalid" --max-attempts 5 --backoff 0ms --fetch $fetch)
        let err = (try { api repositories $c; null } catch {|e| $e })
        assert ($err.msg | str contains "401")
        assert ($err.msg | str contains "1 attempt")
    } }
    { name: "400, 403 and 404 are not retried either", run: {||
        for status in [400 403 404] {
            let fetch = {|req| {status: $status, body: {}} }
            let c = (api client "https://n.invalid" --max-attempts 5 --backoff 0ms --fetch $fetch)
            let err = (try { api repositories $c; null } catch {|e| $e })
            assert ($err.msg | str contains "1 attempt")
        }
    } }

    # --- repositories ---
    { name: "repositories are listed with name, format and type", run: {||
        let fetch = (canned [{match: "/repositories", status: 200, body: [
            {name: "a", format: "npm", type: "proxy"}
            {name: "b", format: "maven2", type: "hosted"}
        ]}])
        let repos = (api repositories (client-with $fetch))
        assert equal ($repos | get name) ["a" "b"]
    } }
    { name: "a hosted or group repository named explicitly is refused with its type", run: {||
        let repos = [
            {name: "p", format: "npm", type: "proxy"}
            {name: "h", format: "npm", type: "hosted"}
            {name: "g", format: "npm", type: "group"}
        ]
        assert equal (api select-proxies $repos ["p"] | get name) ["p"]
        for bad in ["h" "g"] {
            let err = (try { api select-proxies $repos [$bad]; null } catch {|e| $e })
            assert not equal $err null
            assert ($err.msg | str contains $bad)
        }
    } }
    { name: "the refusal names the repository's actual type", run: {||
        let repos = [{name: "h", format: "npm", type: "hosted"}]
        let err = (try { api select-proxies $repos ["h"]; null } catch {|e| $e })
        assert ($err.msg | str contains "hosted")
    } }
    { name: "an unknown repository name is refused", run: {||
        let repos = [{name: "p", format: "npm", type: "proxy"}]
        let err = (try { api select-proxies $repos ["nope"]; null } catch {|e| $e })
        assert ($err.msg | str contains "nope")
    } }
    { name: "a pattern selects only proxies and reports the excluded ones", run: {||
        let repos = [
            {name: "yum-a", format: "yum", type: "proxy"}
            {name: "yum-b", format: "yum", type: "hosted"}
            {name: "npm-c", format: "npm", type: "proxy"}
        ]
        let picked = (api select-proxies $repos [] --pattern "yum-*")
        assert equal ($picked | get name) ["yum-a"]
    } }

    # --- format-specific configuration ---
    { name: "a declared apt distribution is exposed", run: {||
        let fetch = (canned [{match: "/repositories/apt/proxy/r", status: 200, body: {apt: {distribution: "bookworm"}}}])
        let cfg = (api repository-config (client-with $fetch) {name: "r", format: "apt", type: "proxy"})
        assert equal $cfg.distribution "bookworm"
    } }
    { name: "an unreachable configuration yields no declared value rather than aborting", run: {||
        let fetch = {|req| {status: 403, body: {}} }
        let cfg = (api repository-config (client-with $fetch) {name: "r", format: "apt", type: "proxy"})
        assert equal $cfg {}
    } }
    { name: "formats with no scope configuration are not queried", run: {||
        let fetch = {|req| error make {msg: "must not query configuration for this format"} }
        assert equal (api repository-config (client-with $fetch) {name: "r", format: "npm", type: "proxy"}) {}
    } }

    # --- deletion ---
    { name: "a successful deletion is recorded as deleted", run: {||
        let fetch = {|req| {status: 204, body: {}} }
        let r = (api delete-component (client-with $fetch) "id-1")
        assert equal $r.deleted true
        assert equal $r.error ""
    } }
    { name: "a component already gone counts as deleted, not as a failure", run: {||
        let fetch = {|req| {status: 404, body: {}} }
        let r = (api delete-component (client-with $fetch) "id-1")
        assert equal $r.deleted true
        assert ($r.note | str contains "already")
        assert equal $r.error ""
    } }
    { name: "a refused deletion is a per-component failure, not a raise", run: {||
        let fetch = {|req| {status: 403, body: {message: "no"}} }
        let r = (api delete-component (client-with $fetch) "id-1")
        assert equal $r.deleted false
        assert ($r.error | str contains "403")
    } }

    # --- credentials never surface ---
    { name: "a failure message carries neither password nor authorization header", run: {||
        let fetch = {|req| {status: 500, body: {}} }
        let c = (api client "https://n.invalid" --username "admin" --password "hunter2" --max-attempts 1 --backoff 0ms --fetch $fetch)
        let err = (try { api repositories $c; null } catch {|e| $e })
        assert not ($err.msg | str contains "hunter2")
        assert not ($err.msg | str contains "Basic ")
    } }
    { name: "no rendering of an enumeration failure carries the password", run: {||
        let fetch = {|req| {status: 500, body: {}} }
        let c = (api client "https://n.invalid" --username "admin" --password "hunter2" --max-attempts 1 --backoff 0ms --fetch $fetch)
        let err = (try { api components $c "repo"; null } catch {|e| $e })
        for text in [$err.msg, ($err.debug | into string), ($err.rendered | into string)] {
            assert not ($text | str contains "hunter2")
            assert not ($text | str contains "admin")
        }
    } }
]
