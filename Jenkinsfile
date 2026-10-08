// CI/CD for Sprout. Runs on the dockerized Jenkins in ci/ and drives the host Docker daemon.
//
//   Checkout -> Test (backend vs. real Postgres | frontend) -> Build images -> Deploy -> Smoke test
//                                                                          \-> automatic rollback on failure
pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 30, unit: 'MINUTES')
  }

  triggers {
    // Jenkins runs on localhost, so GitHub can't reach it with a webhook; poll the repo instead.
    pollSCM('H/2 * * * *')
  }

  environment {
    IMAGE_TAG     = "${env.BUILD_NUMBER}"
    CI_ID         = "sprout-ci-${env.BUILD_NUMBER}"
    APP_NETWORK   = 'sprout_default'
    // PREVIOUS_TAG is set at runtime in the Deploy stage (not declared here: environment{} values can't be reassigned)
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git log -1 --pretty="format:%h %s (%an)"'
      }
    }

    stage('Test') {
      parallel {
        stage('Backend') {
          steps {
            sh '''
              docker build --target test -t sprout-backend:test-$BUILD_NUMBER backend

              # Throwaway Postgres on a private network, so tests hit the real database engine
              docker network create $CI_ID
              docker run -d --name $CI_ID-db --network $CI_ID \
                -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test \
                postgres:16-alpine
              for i in $(seq 1 30); do
                docker exec $CI_ID-db pg_isready -U test -d test >/dev/null 2>&1 && break
                sleep 1
              done

              docker run --rm --network $CI_ID \
                -e DATABASE_URL=postgresql+psycopg://test:test@$CI_ID-db:5432/test \
                sprout-backend:test-$BUILD_NUMBER pytest -v
            '''
          }
          post {
            always {
              sh '''
                docker rm -f $CI_ID-db || true
                docker network rm $CI_ID || true
                docker rmi sprout-backend:test-$BUILD_NUMBER || true
              '''
            }
          }
        }

        stage('Frontend') {
          steps {
            // The "test" stage of frontend/Dockerfile runs `npm test`; the build fails if tests fail.
            sh 'docker build --target test -t sprout-frontend:test-$BUILD_NUMBER frontend'
          }
          post {
            always { sh 'docker rmi sprout-frontend:test-$BUILD_NUMBER || true' }
          }
        }
      }
    }

    stage('Build images') {
      steps {
        sh '''
          docker build -t sprout-backend:$IMAGE_TAG  -t sprout-backend:latest  backend
          docker build -t sprout-frontend:$IMAGE_TAG -t sprout-frontend:latest frontend
        '''
      }
    }

    stage('Deploy') {
      steps {
        script {
          // Remember what's currently running so we can roll back if the new version is unhealthy.
          env.PREVIOUS_TAG = sh(
            returnStdout: true,
            script: "docker inspect --format '{{.Config.Image}}' sprout-backend-1 2>/dev/null | cut -d: -f2 || true"
          ).trim()
          echo "Currently deployed: ${env.PREVIOUS_TAG ?: 'nothing'} -> deploying ${env.IMAGE_TAG}"
        }
        withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
          sh 'docker compose up -d --no-build --remove-orphans'
        }
      }
    }

    stage('Smoke test') {
      steps {
        // Goes through nginx -> FastAPI -> Postgres, from inside the app's Docker network.
        sh '''
          for i in $(seq 1 30); do
            if docker run --rm --network $APP_NETWORK curlimages/curl:8.11.1 -fsS http://frontend/api/health; then
              echo; echo "Smoke test passed"; exit 0
            fi
            sleep 2
          done
          echo "Smoke test failed"; docker compose logs --tail=50 backend; exit 1
        '''
      }
    }
  }

  post {
    failure {
      script {
        if (env.PREVIOUS_TAG && env.PREVIOUS_TAG != env.IMAGE_TAG) {
          echo "Rolling back to ${env.PREVIOUS_TAG}"
          withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
            sh "IMAGE_TAG=${env.PREVIOUS_TAG} docker compose up -d --no-build --remove-orphans"
          }
        }
      }
    }
    success {
      echo "Sprout build ${env.IMAGE_TAG} is live on http://localhost:8090"
    }
    always {
      sh 'docker image prune -f >/dev/null || true'
    }
  }
}
