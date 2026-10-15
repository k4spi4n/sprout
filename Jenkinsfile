// CI/CD for Sprout. Runs on the dockerized Jenkins in ci/ and drives the host Docker daemon.
//
//   Checkout -> Unit tests -> SonarQube (quality gate) -> Build (compose) -> Integration test
//            -> Push (Docker Hub) -> Deploy -> Smoke test            (+ automatic rollback on failure)
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 45, unit: 'MINUTES')
  }

  triggers {
    // Jenkins runs on localhost, so GitHub can't reach it with a webhook; poll the repo instead.
    pollSCM('H/2 * * * *')
  }

  environment {
    IMAGE_TAG       = "${env.BUILD_NUMBER}"
    // Docker Hub user from ci/.env (via casc.yaml). Without it, images are named local/* and not pushed.
    IMAGE_NAMESPACE = "${env.DOCKERHUB_USER?.trim() ?: 'local'}"
    UNIT_PROJECT    = "sprout-test-${env.BUILD_NUMBER}"
    IT_PROJECT      = "sprout-it-${env.BUILD_NUMBER}"
    APP_NETWORK     = 'sprout_default'
    // PREVIOUS_IMAGE / DEPLOY_STARTED are set at runtime in Deploy (environment{} values can't be reassigned)
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          git log -1 --pretty="format:%h %s (%an)"
          rm -rf reports .scannerwork
          mkdir -p reports/backend reports/frontend reports/e2e
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
              docker cp $UNIT_PROJECT-backend:/app/reports/. reports/backend/ || true
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
              docker cp $UNIT_PROJECT-frontend:/app/reports/. reports/frontend/ || true
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

    stage('SonarQube') {
      steps {
        sh '''
          echo "Waiting for SonarQube at $SONAR_HOST_URL ..."
          for i in $(seq 1 60); do
            curl -fs "$SONAR_HOST_URL/api/system/status" | grep -q '"status":"UP"' && break
            if [ "$i" -eq 60 ]; then echo "SonarQube is not up"; exit 1; fi
            sleep 5
          done

          # Coverage reports were produced inside containers; point them at this workspace's sources
          sed -i "s#<source>.*</source>#<source>$WORKSPACE/backend/app</source>#" reports/backend/coverage.xml
          sed -i "s#^SF:#SF:$WORKSPACE/frontend/#" reports/frontend/coverage/lcov.info
        '''
        withCredentials([usernamePassword(credentialsId: 'sonar-admin', usernameVariable: 'SONAR_USER', passwordVariable: 'SONAR_PASS')]) {
          sh '''
            set +x
            # First run only: replace SonarQube's default admin/admin password with the one from ci/.env
            if ! curl -fs -u "$SONAR_USER:$SONAR_PASS" "$SONAR_HOST_URL/api/authentication/validate" | grep -q '"valid":true'; then
              echo "Setting the SonarQube admin password (first run)"
              curl -fsS -u admin:admin -X POST "$SONAR_HOST_URL/api/users/change_password" \
                --data-urlencode login=admin --data-urlencode previousPassword=admin --data-urlencode "password=$SONAR_PASS"
            fi

            # Short-lived analysis token, valid for this build only
            TOKEN_NAME="ci-$BUILD_TAG"
            SONAR_TOKEN=$(curl -fsS -u "$SONAR_USER:$SONAR_PASS" -X POST "$SONAR_HOST_URL/api/user_tokens/generate" \
              --data-urlencode "name=$TOKEN_NAME" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
            export SONAR_TOKEN

            # sonar-project.properties sets sonar.qualitygate.wait=true: a red Quality Gate fails this step
            rc=0
            sonar-scanner -Dsonar.host.url="$SONAR_HOST_URL" -Dsonar.projectVersion="$BUILD_NUMBER" || rc=$?

            curl -fsS -u "$SONAR_USER:$SONAR_PASS" -X POST "$SONAR_HOST_URL/api/user_tokens/revoke" \
              --data-urlencode "name=$TOKEN_NAME" || true
            echo "SonarQube report: $SONAR_PUBLIC_URL/dashboard?id=sprout"
            exit $rc
          '''
        }
      }
    }

    stage('Build') {
      steps {
        sh '''
          # Image names/tags and the APP_BUILD build arg come from docker-compose.yml
          docker compose build backend frontend
          for svc in backend frontend; do
            docker tag "$IMAGE_NAMESPACE/sprout-$svc:$IMAGE_TAG" "$IMAGE_NAMESPACE/sprout-$svc:latest"
          done
          docker image ls "$IMAGE_NAMESPACE/sprout-*"
        '''
        script {
          if (!env.DOCKERHUB_USER?.trim()) {
            echo 'DOCKERHUB_USER is not set in ci/.env: images stay local and the Push stage will be skipped.'
          }
        }
      }
    }

    stage('Integration test') {
      steps {
        // The release images run in an isolated compose project (own network + database, no published ports)
        sh '''
          IT="docker compose -p $IT_PROJECT -f docker-compose.yml -f docker-compose.it.yml"
          $IT up -d --no-build --wait --wait-timeout 180 db backend frontend
          $IT build e2e
          rc=0
          $IT run --name $IT_PROJECT-e2e e2e || rc=$?
          docker cp $IT_PROJECT-e2e:/e2e/reports/. reports/e2e/ || true
          if [ "$rc" -ne 0 ]; then $IT logs --tail=80 backend frontend; fi
          exit $rc
        '''
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: 'reports/e2e/junit.xml'
          sh '''
            docker rm -f $IT_PROJECT-e2e >/dev/null 2>&1 || true
            docker compose -p $IT_PROJECT -f docker-compose.yml -f docker-compose.it.yml down -v --remove-orphans || true
          '''
        }
      }
    }

    stage('Push') {
      when { expression { return env.DOCKERHUB_USER?.trim() as boolean } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
          sh '''
            # Throwaway Docker config so the login never persists in jenkins_home
            export DOCKER_CONFIG="$(mktemp -d)"
            trap 'docker logout >/dev/null 2>&1; rm -rf "$DOCKER_CONFIG"' EXIT
            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
            docker compose push backend frontend
            for svc in backend frontend; do
              docker push "$IMAGE_NAMESPACE/sprout-$svc:latest"
            done
          '''
        }
        echo "Pushed: https://hub.docker.com/r/${env.IMAGE_NAMESPACE}/sprout-backend and .../sprout-frontend (tags ${env.IMAGE_TAG}, latest)"
      }
    }

    stage('Deploy') {
      steps {
        script {
          // Remember what's running now so a failed release can be rolled back.
          env.PREVIOUS_IMAGE = sh(
            returnStdout: true,
            script: "docker inspect --format '{{.Config.Image}}' sprout-backend-1 2>/dev/null || true"
          ).trim()
          env.DEPLOY_STARTED = 'true'
          echo "Currently deployed: ${env.PREVIOUS_IMAGE ?: 'nothing'} -> deploying ${env.IMAGE_NAMESPACE}/sprout-*:${env.IMAGE_TAG}"
        }
        withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
          sh 'docker compose up -d --no-build --remove-orphans --wait --wait-timeout 180'
        }
      }
    }

    stage('Smoke test') {
      steps {
        // Read-only checks through nginx -> FastAPI -> Postgres, including "is build N really live?"
        sh '''
          docker run --rm -i --network $APP_NETWORK --entrypoint sh curlimages/curl:8.11.1 \
            -s -- http://frontend "$IMAGE_TAG" < scripts/smoke-test.sh
        '''
      }
      post {
        failure { sh 'docker compose logs --tail=80 backend frontend || true' }
      }
    }
  }

  post {
    failure {
      script {
        if (env.DEPLOY_STARTED == 'true') {
          def prev = env.PREVIOUS_IMAGE ?: ''
          if (prev.contains('/sprout-backend:')) {
            def ns = prev.substring(0, prev.indexOf('/sprout-backend:'))
            def tag = prev.substring(prev.lastIndexOf(':') + 1)
            echo "Rolling back to ${prev}"
            withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
              sh "IMAGE_NAMESPACE=${ns} IMAGE_TAG=${tag} docker compose up -d --no-build --remove-orphans"
            }
          } else {
            echo "No previous release to roll back to (${prev ?: 'nothing was deployed'})"
          }
        }
      }
    }
    success {
      echo "Sprout build ${env.IMAGE_TAG} is live on http://localhost:8090"
    }
    always {
      sh '''
        # Keep the 5 newest numbered releases locally (older ones are on Docker Hub if pushing is enabled)
        for svc in backend frontend; do
          docker images "$IMAGE_NAMESPACE/sprout-$svc" --format '{{.Tag}}' | grep -E '^[0-9]+$' | sort -n | head -n -5 \
            | xargs -r -I{} docker rmi "$IMAGE_NAMESPACE/sprout-$svc:{}" >/dev/null 2>&1 || true
        done
        docker image prune -f >/dev/null || true
      '''
    }
  }
}
