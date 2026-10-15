# Jenkins controller with the Docker CLI + Compose plugin and SonarScanner CLI.
# It talks to the host's Docker daemon through the mounted /var/run/docker.sock
# ("Docker outside of Docker"), so the pipeline can build images and deploy containers.
FROM jenkins/jenkins:lts-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg unzip \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# SonarScanner CLI (uses the image's JDK 21)
ARG SONAR_SCANNER_VERSION=7.2.0.5079
RUN curl -fsSL -o /tmp/sonar-scanner.zip \
      "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip" \
 && unzip -q /tmp/sonar-scanner.zip -d /opt \
 && mv "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}" /opt/sonar-scanner \
 && rm /tmp/sonar-scanner.zip
ENV PATH="/opt/sonar-scanner/bin:${PATH}"
USER jenkins

# Plugins + Configuration as Code (admin user, credentials and the "sprout" pipeline job)
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/casc.yaml

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
