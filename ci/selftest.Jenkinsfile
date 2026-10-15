// Create a separate Pipeline-from-SCM job using this script path before the first release.
pipeline {
  agent any
  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 10, unit: 'MINUTES')
  }
  stages {
    stage('Toolchain and Compose') {
      steps {
        sh '''
          docker version
          docker compose version
          docker compose config --quiet
          docker compose -f docker-compose.test.yml config --quiet
        '''
        script {
          def scanner = env.SPROUT_SCANNER_HOME?.trim() ?: tool('sonar-scanner')
          withEnv(["SCANNER_HOME=${scanner}"]) {
            sh '"$SCANNER_HOME/bin/sonar-scanner" --version'
          }
        }
      }
    }
    stage('Analysis access') {
      steps {
        withSonarQubeEnv('SonarQube') {
          withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
            sh '''
              set +x
              test -n "$SONAR_TOKEN"
              curl --connect-timeout 5 --max-time 15 -fsS -u "$SONAR_TOKEN:" \
                "$SONAR_HOST_URL/api/authentication/validate" | grep -q '"valid":true'
              echo 'SonarQube analysis credential is valid'
            '''
          }
        }
      }
    }
    stage('Deployment credential') {
      steps {
        withCredentials([string(credentialsId: 'sprout-db-password', variable: 'POSTGRES_PASSWORD')]) {
          sh '''
            set +x
            [ "${#POSTGRES_PASSWORD}" -ge 20 ] || { echo 'Database password must have at least 20 characters'; exit 1; }
          '''
        }
      }
    }
  }
}
