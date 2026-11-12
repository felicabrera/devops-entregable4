# Jenkins con las herramientas que usa el Jenkinsfile: docker CLI (buildx), kubectl,
# helm, trivy, semgrep, snyk, kyverno y python3. Los plugins se instalan en el build.
FROM jenkins/jenkins:2.580.2-lts-jdk21

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.34.1
ARG HELM_VERSION=v3.19.0
ARG KYVERNO_VERSION=v1.19.2
ARG TRIVY_VERSION=0.76.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg git jq python3 python3-venv python3-pip \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz -C /tmp \
    && mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm && rm -rf /tmp/linux-* \
    && curl -fsSLo /usr/local/bin/kyverno.tar.gz "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/kyverno-cli_${KYVERNO_VERSION}_linux_$( [ "$TARGETARCH" = amd64 ] && echo x86_64 || echo arm64 ).tar.gz" \
    && tar -xzf /usr/local/bin/kyverno.tar.gz -C /usr/local/bin kyverno && rm /usr/local/bin/kyverno.tar.gz \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-$( [ "$TARGETARCH" = amd64 ] && echo 64bit || echo ARM64 ).tar.gz" | tar -xz -C /usr/local/bin trivy \
    && pip3 install --no-cache-dir --break-system-packages semgrep==1.185.0 \
    && curl -fsSLo /usr/local/bin/snyk "https://downloads.snyk.io/cli/stable/snyk-linux$( [ "$TARGETARCH" = arm64 ] && echo -arm64 )" \
    && chmod +x /usr/local/bin/snyk \
    && kubectl version --client && helm version --short && kyverno version && trivy --version && semgrep --version && snyk --version

# El usuario jenkins necesita acceso al socket de Docker del host (gid se fija en docker-compose)
ARG DOCKER_GID=999
RUN groupadd -g ${DOCKER_GID} docker-host 2>/dev/null || true \
    && usermod -aG ${DOCKER_GID} jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

USER jenkins
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG=/var/jenkins_config/casc.yaml
