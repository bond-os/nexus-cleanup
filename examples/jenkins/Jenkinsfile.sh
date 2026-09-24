// nexus-cleanup — declarative pipeline using plain `sh` steps, for a Jenkins
// without the Docker Pipeline plugin.
//
// Needs:
//   - an agent labelled `docker` with the docker CLI and access to a daemon
//   - a "Username with password" credential with the id `nexus-cleanup`
// Point the job's Script Path at this file.
//
// The workspace is bind-mounted into the container, so if the agent itself runs
// in a container talking to the host's daemon, $WORKSPACE must be a path that
// exists on the Docker host.
//
// Every build performs a dry run and archives its report. Deletion happens only in
// a build started by hand with EXECUTE ticked, only after someone approves the
// dry-run report, and never in a build started by the timer.

pipeline {
    // Per-stage agents, so the approval prompt waits without holding an executor.
    agent none

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '60'))
    }

    triggers {
        cron('H 3 * * *')
    }

    parameters {
        string(name: 'PATTERN', defaultValue: 'yum-proxy-*',
               description: 'Glob selecting the proxy repositories to clean')
        string(name: 'KEEP', defaultValue: '2',
               description: 'Newest versions to retain per group')
        string(name: 'MAX_DELETIONS', defaultValue: '500',
               description: 'Abort an executing run above this many deletions')
        booleanParam(name: 'EXECUTE', defaultValue: false,
                     description: 'Delete after the dry run is approved. Ignored on timer-triggered builds.')
    }

    environment {
        NEXUS_URL = 'https://nexus.example.com'
        // Pinned to the version floor in AGENTS.md.
        NUSHELL_IMAGE = 'ghcr.io/nushell/nushell:0.115.1-alpine'
    }

    // In both `docker run` calls below:
    //   - no `-t`: a TTY merges stderr into stdout, and stdout is the report
    //   - `--env NAME` without a value passes the variable through, so the
    //     credentials never appear on a command line
    //   - `--user` keeps the report files owned by the agent user

    stages {
        stage('Dry run') {
            agent { label 'docker' }
            steps {
                script { checkExecuteParameters() }
                withCredentials([usernamePassword(credentialsId: 'nexus-cleanup',
                        usernameVariable: 'NEXUS_USERNAME', passwordVariable: 'NEXUS_PASSWORD')]) {
                    script {
                        handleExit(sh(returnStatus: true, script: '''
                            docker run --rm \
                                --user "$(id -u):$(id -g)" \
                                --volume "$WORKSPACE:/work" --workdir /work \
                                --env NEXUS_URL --env NEXUS_USERNAME --env NEXUS_PASSWORD \
                                --entrypoint nu "$NUSHELL_IMAGE" \
                                nexus-cleanup.nu --pattern "$PATTERN" --keep "$KEEP" --fail-on-skip \
                                    --summary-out summary-dry-run.json > report-dry-run.json
                        '''))
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: '*-dry-run.json', allowEmptyArchive: true
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
                message 'Delete the components marked "delete" in report-dry-run.json?'
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
                                --env NEXUS_URL --env NEXUS_USERNAME --env NEXUS_PASSWORD \
                                --entrypoint nu "$NUSHELL_IMAGE" \
                                nexus-cleanup.nu --pattern "$PATTERN" --keep "$KEEP" \
                                    --max-deletions "$MAX_DELETIONS" --execute \
                                    --summary-out summary-execute.json > report-execute.json
                        '''))
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: '*-execute.json', allowEmptyArchive: true
                }
            }
        }
    }
}

// Refuse EXECUTE without a deletion cap, before anything is enumerated.
void checkExecuteParameters() {
    if (params.EXECUTE && !(params.MAX_DELETIONS ==~ /[1-9][0-9]*/)) {
        error 'EXECUTE needs MAX_DELETIONS set to a positive whole number'
    }
}

// Maps the exit codes documented in README.md onto build results.
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
