# Jenkins controller with the Docker CLI + Compose plugin and SonarScanner CLI.
# It talks to the host's Docker daemon through the mounted /var/run/docker.sock
# ("Docker outside of Docker"), so the pipeline can build images and deploy containers.
FROM jenkins/jenkins:lts-jdk21@sha256:a660310e39ade10631f774bacd5219de767dfd08947ea5c32a739b5e5bb382c1

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
ARG SONAR_SCANNER_SHA256=30d80b37c8f4be1254b6c43ec8c64291798d97a710c28475958b5e2f10809fe1
RUN curl -fsSL -o /tmp/sonar-scanner.zip \
      "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip" \
 && echo "${SONAR_SCANNER_SHA256}  /tmp/sonar-scanner.zip" | sha256sum -c - \
 && unzip -q /tmp/sonar-scanner.zip -d /opt \
 && mv "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}" /opt/sonar-scanner \
 && rm /tmp/sonar-scanner.zip
ENV PATH="/opt/sonar-scanner/bin:${PATH}"
USER jenkins

# Plugins + Configuration as Code (admin user, credentials and the "sprout" pipeline job)
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --latest=false --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/casc.yaml

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
