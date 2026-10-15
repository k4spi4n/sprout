// CI/CD for Sprout. Runs on the dockerized Jenkins in ci/ and drives the host Docker daemon.
//
// Build once, scan and test the release images, then deploy their exact image IDs.
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout()
    skipStagesAfterUnstable()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 45, unit: 'MINUTES')
  }

  triggers {
    // Jenkins runs on localhost, so GitHub can't reach it with a webhook; poll the repo instead.
    pollSCM('H/2 * * * *')
  }

  parameters {
    booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Deploy after all quality, security and integration gates pass')
    booleanParam(name: 'PUSH_IMAGE', defaultValue: false, description: 'Push release images using registry-credentials')
    string(name: 'IMAGE_NAMESPACE', defaultValue: '', description: 'Docker Hub user or organisation; blank uses DOCKERHUB_USER or local')
  }

  environment {
    // Docker Hub user from ci/.env (via casc.yaml). Without it, images are named local/* and not pushed.
    IMAGE_NAMESPACE = "${params.IMAGE_NAMESPACE?.trim() ?: env.DOCKERHUB_USER?.trim() ?: 'local'}"
    UNIT_PROJECT    = "sprout-test-${env.BUILD_NUMBER}"
    IT_PROJECT      = "sprout-it-${env.BUILD_NUMBER}"
    APP_PROJECT     = 'sprout'
    BACKUP_DIR      = "${env.JENKINS_HOME}/sprout-backups"
    RELEASE_STATE_DIR = '.releases'
    TRIVY_IMAGE     = 'aquasec/trivy@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.APP_REVISION = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.APP_REVISION.take(12)}"
          if (!(env.IMAGE_NAMESPACE ==~ /[a-z0-9]+([._-][a-z0-9]+)*/)) {
            error('IMAGE_NAMESPACE must be a Docker Hub user or organisation name')
          }
          if (params.PUSH_IMAGE && env.IMAGE_NAMESPACE == 'local') {
            error('Set IMAGE_NAMESPACE to your Docker Hub user or organisation before pushing')
          }
        }
        sh '''
          git log -1 --pretty="format:%h %s (%an)"
          rm -rf reports .scannerwork
          mkdir -p reports/backend reports/frontend reports/e2e reports/security reports/release
          docker compose config --quiet
          docker compose -f docker-compose.test.yml config --quiet
          docker compose -f docker-compose.yml -f docker-compose.it.yml config --quiet
          sh scripts/test-release-failures.sh
        '''
      }
    }

    stage('Unit tests') {
      parallel {
        stage('Backend (pytest + PostgreSQL)') {
          steps {
            // docker-compose.test.yml starts a throwaway Postgres, so tests run on the real database engine
            sh '''
              UT="docker compose -p $UNIT_PROJECT-be -f docker-compose.test.yml"
              $UT build backend-tests
              rc=0
              $UT run --name $UNIT_PROJECT-backend backend-tests || rc=$?
              docker cp $UNIT_PROJECT-backend:/app/reports/. reports/backend/ || rc=1
              exit $rc
            '''
          }
          post {
            always {
              junit allowEmptyResults: true, testResults: 'reports/backend/junit.xml'
              sh '''
                docker rm -f $UNIT_PROJECT-backend >/dev/null 2>&1 || true
                docker compose -p $UNIT_PROJECT-be -f docker-compose.test.yml down -v --remove-orphans || true
              '''
            }
          }
        }

        stage('Frontend (vitest + Testing Library)') {
          steps {
            sh '''
              UT="docker compose -p $UNIT_PROJECT-fe -f docker-compose.test.yml"
              $UT build frontend-tests
              rc=0
              $UT run --name $UNIT_PROJECT-frontend frontend-tests || rc=$?
              docker cp $UNIT_PROJECT-frontend:/app/reports/. reports/frontend/ || rc=1
              exit $rc
            '''
          }
          post {
            always {
              junit allowEmptyResults: true, testResults: 'reports/frontend/junit.xml'
              sh '''
                docker rm -f $UNIT_PROJECT-frontend >/dev/null 2>&1 || true
                docker compose -p $UNIT_PROJECT-fe -f docker-compose.test.yml down -v --remove-orphans || true
              '''
            }
          }
        }
      }
    }

    stage('SonarQube Analysis') {
      steps {
        sh '''
          # Coverage reports were produced inside containers; point them at this workspace's sources
          sed -i "s#<source>.*</source>#<source>$WORKSPACE/backend/app</source>#" reports/backend/coverage.xml
          sed -i "s#^SF:#SF:$WORKSPACE/frontend/#" reports/frontend/coverage/lcov.info
        '''
        withSonarQubeEnv('SonarQube') {
          // Scanner is installed in ci/jenkins/Dockerfile, or configured as a portal tool.
          script {
            def scanner = env.SPROUT_SCANNER_HOME?.trim() ?: tool('sonar-scanner')
            withEnv(["SCANNER_HOME=${scanner}"]) {
              sh '"$SCANNER_HOME/bin/sonar-scanner" -Dsonar.projectVersion="$IMAGE_TAG" -Dsonar.scm.revision="$APP_REVISION"'
            }
          }
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Build') {
      steps {
        sh '''
          # Image names/tags and the APP_BUILD build arg come from docker-compose.yml
          docker compose build backend frontend
          docker image ls "$IMAGE_NAMESPACE/sprout-*"
        '''
        script {
          env.BACKEND_IMAGE = sh(returnStdout: true, script: 'docker image inspect --format "{{.Id}}" "$IMAGE_NAMESPACE/sprout-backend:$IMAGE_TAG"').trim()
          env.FRONTEND_IMAGE = sh(returnStdout: true, script: 'docker image inspect --format "{{.Id}}" "$IMAGE_NAMESPACE/sprout-frontend:$IMAGE_TAG"').trim()
          if (!params.PUSH_IMAGE) {
            echo 'PUSH_IMAGE=false: the tested images stay local.'
          }
        }
      }
    }

    stage('Security and SBOM') {
      steps {
        sh '''
          set -eu
          # Scan committed sources for secrets without mounting the Jenkins workspace on the host.
          git archive HEAD | docker run --rm -i --entrypoint sh "$TRIVY_IMAGE" -c \
            'mkdir /tmp/source && tar -xf - -C /tmp/source && trivy fs --scanners secret --severity HIGH,CRITICAL --exit-code 1 /tmp/source'
          for svc in backend frontend; do
            image="$IMAGE_NAMESPACE/sprout-$svc:$IMAGE_TAG"
            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
              -v sprout-trivy-cache:/root/.cache/trivy "$TRIVY_IMAGE" image \
              --image-src docker --no-progress --scanners vuln --ignore-unfixed --severity HIGH,CRITICAL --exit-code 1 "$image"
            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
              -v sprout-trivy-cache:/root/.cache/trivy "$TRIVY_IMAGE" image \
              --image-src docker --format cyclonedx "$image" > "reports/security/$svc.cdx.json"
          done
          # These use the same locked dependency installs as the unit tests.
          docker compose -p "$UNIT_PROJECT-be" -f docker-compose.test.yml run --rm --no-deps \
            backend-tests pip-audit --progress-spinner off --strict
          docker compose -p "$UNIT_PROJECT-fe" -f docker-compose.test.yml run --rm --no-deps \
            frontend-tests npm audit --audit-level=moderate
        '''
      }
    }

    stage('Integration test') {
      steps {
        // The release images run in an isolated compose project (own network + database, no published ports)
        sh '''
          export APP_PROJECT="$IT_PROJECT" POSTGRES_PASSWORD='ci-only-disposable-password-123' SPROUT_PRODUCTION=1
          export COMPOSE_FILE=docker-compose.yml:docker-compose.production.yml:docker-compose.it.yml
          sh scripts/prepare-db-secret.sh
          IT="docker compose -p $IT_PROJECT"
          $IT up -d --no-build --wait --wait-timeout 180 db backend frontend
          $IT build e2e
          rc=0
          $IT run --name $IT_PROJECT-e2e e2e || rc=$?
          docker cp $IT_PROJECT-e2e:/e2e/reports/. reports/e2e/ || rc=1
          if [ "$rc" -eq 0 ]; then
            sh scripts/test-recovery.sh > reports/e2e/recovery.log 2>&1 || rc=$?
            cat reports/e2e/recovery.log
          fi
          if [ "$rc" -ne 0 ]; then $IT logs --tail=80 backend frontend; fi
          exit $rc
        '''
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'reports/e2e/junit.xml'
          sh '''
            docker rm -f $IT_PROJECT-e2e >/dev/null 2>&1 || true
            docker compose -p $IT_PROJECT -f docker-compose.yml -f docker-compose.production.yml -f docker-compose.it.yml down -v --remove-orphans || true
          '''
        }
      }
    }

    stage('Push') {
      when { expression { return params.PUSH_IMAGE } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'registry-credentials', usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
          sh '''
            # Throwaway Docker config so the login never persists in jenkins_home
            export DOCKER_CONFIG="$(mktemp -d)"
            trap 'docker logout >/dev/null 2>&1; rm -rf "$DOCKER_CONFIG"' EXIT
            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
            for svc in backend frontend; do
              docker push "$IMAGE_NAMESPACE/sprout-$svc:$IMAGE_TAG"
            done
          '''
        }
        echo "Pushed tested release ${env.IMAGE_TAG}; deployment uses the tested image IDs."
      }
    }

    stage('Release (backup, migrate, deploy, smoke)') {
      when {
        expression {
          def branch = env.BRANCH_NAME ?: env.GIT_BRANCH
          return params.DEPLOY && !env.CHANGE_ID && branch in ['main', 'origin/main']
        }
      }
      steps {
        withEnv(['COMPOSE_FILE=docker-compose.yml:docker-compose.production.yml', 'SPROUT_PRODUCTION=1']) {
          withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
            sh 'sh scripts/deploy.sh'
          }
        }
        script { env.RELEASE_DEPLOYED = 'true' }
      }
    }
  }

  post {
    unsuccessful {
      script {
        if (fileExists('.releases/pending')) {
          withEnv(['COMPOSE_FILE=docker-compose.yml:docker-compose.production.yml']) {
            withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
              sh 'sh scripts/deploy.sh rollback'
            }
          }
        }
      }
    }
    success {
      echo "Sprout ${env.IMAGE_TAG}: all gates passed${env.RELEASE_DEPLOYED == 'true' ? '; deployed at http://localhost:8090' : '; deployment skipped'}"
    }
    cleanup {
      sh '''
        mkdir -p reports/release
        if [ -n "${BACKEND_IMAGE:-}" ] && [ -n "${FRONTEND_IMAGE:-}" ]; then
          docker image inspect "$BACKEND_IMAGE" "$FRONTEND_IMAGE" > reports/release/images.json || true
        fi
        if [ -f .releases/current.env ]; then cp .releases/current.env reports/release/; fi
        if [ -f .releases/previous.env ]; then cp .releases/previous.env reports/release/; fi
        # Only clean this build's disposable projects; retain images needed for recovery.
        docker compose -p "$UNIT_PROJECT-be" -f docker-compose.test.yml down -v --remove-orphans || true
        docker compose -p "$UNIT_PROJECT-fe" -f docker-compose.test.yml down -v --remove-orphans || true
        docker compose -p "$IT_PROJECT" -f docker-compose.yml -f docker-compose.production.yml -f docker-compose.it.yml down -v --remove-orphans || true
      '''
      archiveArtifacts artifacts: 'reports/**/*', allowEmptyArchive: true, fingerprint: true
    }
  }
}
