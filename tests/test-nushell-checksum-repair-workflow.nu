use ./harness.nu *

const WORKFLOW = ".github/workflows/repair-nushell-checksum.yml"

run-suite "Nushell checksum repair workflow" [
    { name: "it runs only after a completed tests workflow", run: {||
        let text = (open --raw $WORKFLOW)
        assert ($text | str contains "workflow_run:")
        assert ($text | str contains "workflows: [tests]")
        assert ($text | str contains "types: [completed]")
        assert ($text | str contains "github.event.workflow_run.conclusion == 'failure'")
        assert ($text | str contains "github.event.workflow_run.event == 'pull_request'")
    } }
    { name: "it uses least permissions and trusted maintenance code", run: {||
        let text = (open --raw $WORKFLOW)
        assert ($text | str contains "permissions: {}")
        assert ($text | str contains "contents: write")
        assert ($text | str contains "actions: write")
        assert not ($text | str contains "pull-requests: write")
        assert ($text | str contains "path: trusted")
        assert ($text | str contains "persist-credentials: false")
        assert ($text | str contains "../trusted/.github/scripts/repair-nushell-checksum.sh")
    } }
    { name: "it requires the Renovate Nushell identity and exact failed check", run: {||
        let text = (open --raw $WORKFLOW)
        assert ($text | str contains '.user.login == "renovate[bot]"')
        assert ($text | str contains '.head.ref == "renovate/nushell"')
        assert ($text | str contains '.head.sha == $sha')
        assert ($text | str contains 'pr=$(gh api "repos/$REPOSITORY/pulls/$pr_number")')
        assert ($text | str contains '.commits == 1')
        assert ($text | str contains "pull request #$pr_number is no longer eligible")
        assert ($text | str contains 'select(.name == "nushell-checksum")')
        assert ($text | str contains '["failure"]')
    } }
    { name: "it allows only Nushell pin files and the two checksum outputs", run: {||
        let text = (open --raw $WORKFLOW)
        for file in [
            "Containerfile"
            ".github/workflows/tests.yml"
            "README.md"
            "AGENTS.md"
            "nexus-cleanup/templates/ci/forgejo/.forgejo/workflows/nexus-cleanup.yml"
            "examples/forgejo/.forgejo/workflows/nexus-cleanup.yml"
        ] {
            assert ($text | str contains $"\"($file)\"")
        }
        assert ($text | str contains 'git status --short |')
        assert ($text | str contains "Refusing to amend: unexpected changed files.")
    } }
    { name: "it conditionally pushes and reruns tests without merging", run: {||
        let text = (open --raw $WORKFLOW)
        assert ($text | str contains "group: repair-nushell-checksum")
        assert ($text | str contains "cancel-in-progress: false")
        assert ($text | str contains "git commit --amend --no-edit")
        assert ($text | str contains "git add \\")
        assert ($text | str contains "fetch-depth: 0")
        assert ($text | str contains 'original_parent=$(git rev-parse "$RUN_HEAD_SHA^")')
        assert ($text | str contains '"$(git rev-parse HEAD^)" != "$original_parent"')
        assert ($text | str contains '--force-with-lease="refs/heads/renovate/nushell:$RUN_HEAD_SHA"')
        assert ($text | str contains "actions/workflows/tests.yml/dispatches")
        assert not ($text | str contains "gh pr merge")
        assert not ($text | str contains "gh pr review")
    } }
    { name: "maintainer guidance documents automation and the manual fallback", run: {||
        let agents = (open --raw "AGENTS.md")
        let renovate = (open --raw "renovate.json")
        assert ($agents | str contains "trusted `repair-nushell-checksum` workflow")
        assert ($agents | str contains "**amends** the existing commit")
        assert ($agents | str contains "required checksum check remains the independent gate")
        assert ($agents | str contains "perform those same steps manually as the fallback")
        assert ($renovate | str contains "trusted `repair-nushell-checksum` workflow")
        assert ($renovate | str contains "never merges or approves the pull request")
        assert ($renovate | str contains "**amends** this commit")
    } }
]
