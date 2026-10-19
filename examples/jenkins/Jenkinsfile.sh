// nexus-cleanup — declarative pipeline using plain `sh` steps, for a Jenkins
// without the Docker Pipeline plugin.
//
// Needs:
//   - an agent labelled `docker` with the docker CLI and access to a daemon
//   - a "Username with password" credential with the id `nexus-cleanup`
//   - max-deletions or max-deletion-share in every configuration file: the loop
//     passes --require-cap, so a file without a cap fails the dry run
//
// Use as the Jenkinsfile of a private repository that holds the configuration
// files: one YAML file per cleanup under CONFIG_DIR, and ci/run-configs.sh, the
// loop that runs the tool once per file. Adding a file needs no change here.
// The tool comes from the published image, pinned to an exact release. Bump the
// pinned version deliberately, after reading CHANGELOG.md.
//
// The workspace is bind-mounted into the container, so if the agent itself runs
// in a container talking to the host's daemon, $WORKSPACE must be a path that
// exists on the Docker host.
//
// Every build performs a dry run of every configuration file and archives the
// reports. Deletion happens only in a build started by hand with EXECUTE ticked,
// only after someone approves the dry-run reports, and never in a build started by
// the timer.

pipeline {
    // Per-stage agents, so the approval prompt waits without holding an executor.
    agent none

    options {
        disableConcurrentBuilds()
        // Each stage checks out this repository: the configuration files and the
        // loop script live in it.
        buildDiscarder(logRotator(numToKeepStr: '60'))
    }

    triggers {
        cron('H 3 * * *')
    }

    parameters {
        booleanParam(name: 'EXECUTE', defaultValue: false,
                     description: 'Delete after the dry run is approved. Ignored on timer-triggered builds.')
    }

    environment {
        NEXUS_URL = 'https://nexus.example.com'
        // In your own repository this is `configs`; this example reads the files
        // shipped beside it.
        CONFIG_DIR = 'examples/configs'
        // An exact release, never a floating tag.
        NEXUS_CLEANUP_IMAGE = 'ghcr.io/bond-os/nexus-cleanup:0.1.0'
    }

    // In both `docker run` calls below:
    //   - no `-t`: a TTY merges stderr into stdout, which the loop keeps apart
    //   - `--entrypoint sh` runs the loop script inside the image, where the tool
    //     is on PATH
    //   - `--env NAME` without a value passes the variable through, so the
    //     credentials never appear on a command line
    //   - `--user` keeps the report files owned by the agent user. That holds
    //     for a rootful Docker daemon only. A rootless runtime maps the agent's
    //     uid to container root, so the same uid inside cannot write $WORKSPACE.
    //     Under rootless Podman, add `--userns=keep-id` next to `--user`, which
    //     maps the agent's uid to itself. Under rootless Docker, replace `--user`
    //     with `--user 0:0`, which maps to the agent user.

    stages {
        stage('Dry run') {
            agent { label 'docker' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-cleanup',
                        usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        handleExit(sh(returnStatus: true, script: '''
                            docker run --rm \
                                --user "$(id -u):$(id -g)" \
                                --volume "$WORKSPACE:/work" --workdir /work \
                                --env NEXUS_URL --env NEXUS_USERNAME --env NEXUS_PASSWORD --env CONFIG_DIR \
                                --entrypoint sh "$NEXUS_CLEANUP_IMAGE" examples/ci/run-configs.sh
                        '''))
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'reports/*.dry-run*.json', allowEmptyArchive: true
                }
            }
        }

        stage('Execute') {
            when {
                beforeAgent true
                beforeInput true
                allOf {
                    expression { params.EXECUTE }
                    not { triggeredBy 'TimerTrigger' }
                }
            }
            options {
                timeout(time: 24, unit: 'HOURS')
            }
            input {
                message 'Delete the components marked "delete" in the dry-run reports?'
                ok 'Delete'
                // submitter 'nexus-admins'
            }
            agent { label 'docker' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'nexus-cleanup',
                        usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        handleExit(sh(returnStatus: true, script: '''
                            docker run --rm \
                                --user "$(id -u):$(id -g)" \
                                --volume "$WORKSPACE:/work" --workdir /work \
                                --env NEXUS_URL --env NEXUS_USERNAME --env NEXUS_PASSWORD --env CONFIG_DIR \
                                --entrypoint sh "$NEXUS_CLEANUP_IMAGE" examples/ci/run-configs.sh --execute
                        '''))
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'reports/*.execute*.json', allowEmptyArchive: true
                }
            }
        }
    }
}

// Maps the exit codes documented in README.md onto build results. The loop ends
// with the first code other than 0 and 4, else 4, else 0, so the same mapping holds.
void handleExit(int status) {
    switch (status) {
        case 0:
            return
        case 1:
            unstable 'some deletions failed; see the report'
            return
        case 4:
            unstable 'some groups were skipped; see the report'
            return
        case 2:
            error 'usage or configuration error; nothing was enumerated'
        case 3:
            error 'Nexus unreachable or enumeration failed; nothing was deleted'
        case 5:
            error 'deletion cap exceeded; nothing was deleted'
        default:
            error "nexus-cleanup exited with ${status}"
    }
}
