use ./harness.nu *
use ../tools/record-fixtures.nu *

# A component page shaped like Nexus' own, carrying an instance hostname, a real
# username, an uploader IP and a blob store name — plus a field the tool does
# not know about, which must survive untouched.
const HOST = "nexus.internal.example.org"
const USER = "bernard.bondos"
const PASSWORD = "hunter2-correct-horse"

def sample []: nothing -> record {
    {
        items: [
            {
                id: "bWF2ZW4tY2VudHJhbDo..."
                repository: "maven-central"
                format: "maven2"
                group: "org.example"
                name: "widget"
                version: "1.2.3"
                someFutureField: "keep me"
                assets: [
                    {
                        downloadUrl: $"https://($HOST):8443/repository/maven-central/org/example/widget/1.2.3/widget-1.2.3.jar"
                        path: "org/example/widget/1.2.3/widget-1.2.3.jar"
                        fileSize: 4096
                        uploader: $USER
                        uploaderIp: "10.20.30.40"
                        blobStoreName: "internal-blobs"
                        maven2: {extension: "jar", groupId: "org.example", artifactId: "widget"}
                    }
                ]
            }
        ]
        continuationToken: null
    }
}

def redacted []: nothing -> record {
    redact (sample) --hosts (hosts-of $"https://($HOST):8443") --secrets [$USER $PASSWORD]
}

def as-text []: nothing -> string { redacted | to json }

run-suite "fixture redaction" [
    { name: "the instance hostname does not survive redaction", run: {||
        assert not ((as-text) | str contains $HOST)
    } }
    { name: "the host:port form does not survive either", run: {||
        assert not ((as-text) | str contains $"($HOST):8443")
    } }
    { name: "the username does not survive redaction", run: {||
        assert not ((as-text) | str contains $USER)
    } }
    { name: "the password does not survive redaction", run: {||
        assert not ((as-text) | str contains $PASSWORD)
    } }
    { name: "identity fields are replaced wholesale, at any depth", run: {||
        let asset = (redacted | get items.0.assets.0)
        assert equal $asset.uploader "redacted-user"
        assert equal $asset.uploaderIp "0.0.0.0"
        assert equal $asset.blobStoreName "redacted-blobstore"
    } }
    { name: "the download URL keeps its path but loses the host", run: {||
        let url = (redacted | get items.0.assets.0.downloadUrl)
        assert ($url | str contains "/repository/maven-central/org/example/widget/1.2.3/widget-1.2.3.jar")
        assert ($url | str contains $PLACEHOLDER_HOST)
    } }
    { name: "everything the tool actually reads survives unchanged", run: {||
        let c = (redacted | get items.0)
        assert equal $c.name "widget"
        assert equal $c.version "1.2.3"
        assert equal $c.group "org.example"
        assert equal $c.format "maven2"
        assert equal $c.assets.0.fileSize 4096
        assert equal $c.assets.0.maven2.extension "jar"
    } }
    { name: "unknown fields are preserved rather than dropped", run: {||
        assert equal (redacted | get items.0.someFutureField) "keep me"
    } }
    { name: "structure is preserved, including nulls", run: {||
        assert equal (redacted | get continuationToken) null
        assert equal (redacted | get items | length) 1
    } }
    { name: "a secret too short to be safe is not substituted", run: {||
        # Substituting a 2-character secret would corrupt unrelated text.
        let out = (redact {note: "the maven2 format"} --hosts [] --secrets ["en"] | get note)
        assert equal $out "the maven2 format"
    } }
]
