#!/usr/bin/env nu
# Development only: writes examples/<system>/ for every CI system, exactly as
# `nexus-cleanup init --ci <system> --editor vscode --editor intellij --env varlock`
# writes it at VERSION, plus release-please markers on every pinned line, so that a
# release PR moves the examples' pins together with nexus-cleanup/version.nu. Never
# edit those trees by hand — change the templates in nexus-cleanup/templates/ and run
# this.
# tests/test-examples.nu fails if the two disagree.
#
#   nu tools/render-examples.nu

use ../nexus-cleanup/scaffold.nu *
use ../nexus-cleanup/version.nu [VERSION]

# What examples/<ci>/ holds, as `scaffold plan` returns it.
export def example-plan [ci: string]: nothing -> list<record<path: string, content: string>> {
    scaffold plan --ci $ci --editor [vscode intellij] --env-tool [varlock] --version $VERSION --release-markers
}

def main [] {
    let examples = ($env.FILE_PWD | path dirname | path join "examples")
    for ci in ($CI_SYSTEMS | columns) {
        let dir = ($examples | path join $ci)
        # Wholly generated: removing it first means a file dropped from the
        # templates does not linger here.
        rm -rf $dir
        scaffold write (example-plan $ci) $dir --quiet
        print --stderr $"render-examples: wrote ($dir)"
    }
}
