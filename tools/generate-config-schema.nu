#!/usr/bin/env nu
# Development only: writes schema/config.schema.json from the configuration key
# table in nexus-cleanup/config.nu. Never edit the schema by hand — change the
# table and run this. tests/test-config-schema.nu fails if the two disagree.
#
#   nu tools/generate-config-schema.nu

use ../nexus-cleanup/config.nu [CONFIG_KEYS REFUSED_KEYS SCHEMA_KEY]

const JSON_TYPES = {
    string: {type: "string"}
    duration: {type: "string"}
    int: {type: "integer"}
    number: {type: "number"}
    bool: {type: "boolean"}
    "list<string>": {type: "array", items: {type: "string"}}
}

# Sort record keys at every level, so the output is stable and diffs stay small.
def sorted [value: any]: nothing -> any {
    match ($value | describe | str replace --regex '<.*' '') {
        "record" => ($value | columns | sort | reduce --fold {} {|k, acc| $acc | insert $k (sorted ($value | get $k)) })
        "list" | "table" => ($value | each {|v| sorted $v })
        _ => $value
    }
}

# The schema as JSON text, exactly as committed.
export def config-schema []: nothing -> string {
    mut properties = {}
    $properties = ($properties | insert $SCHEMA_KEY {
        type: "string"
        description: "Address of this schema, for editors. Read and ignored by the tool."
    })
    for row in $CONFIG_KEYS {
        $properties = ($properties | insert $row.key (
            $JSON_TYPES | get $row.type | merge $row.schema | merge {description: $row.description}
        ))
    }
    for row in $REFUSED_KEYS {
        # `not: {}` never validates, like the schema `false`, but can carry a description.
        $properties = ($properties | insert $row.key {not: {}, description: $row.description})
    }

    let schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema"
        title: "nexus-cleanup configuration"
        description: "Settings for one nexus-cleanup run, keyed by flag name. Flags override the file; --execute is never a file setting."
        type: "object"
        additionalProperties: false
        properties: $properties
    }
    (sorted $schema | to json --indent 2) + "\n"
}

def main [] {
    let out = ($env.FILE_PWD | path dirname | path join "schema" "config.schema.json")
    mkdir ($out | path dirname)
    config-schema | save --force --raw $out
    print --stderr $"generate-config-schema: wrote ($out)"
}
