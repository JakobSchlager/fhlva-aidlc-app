# Devcontainer image for fhlva-aidlc-app: development, test and deployment toolchain on Podman.
# See openspec/changes/archive/2026-10-07-add-podman-devcontainer (design.md) for the reasoning behind each choice.
#
# Base: quay.io/podman/stable (Fedora). Podman runs inside the container, which the host starts
# privileged. Its default containers.conf forces host namespaces, which breaks minikube's node
# container, so it is replaced below.
FROM quay.io/podman/stable:latest
USER root

# Versions are pinned where a release artefact exists. Distro packages (JDK, PostgreSQL client,
# Podman, compose provider) follow the base image's Fedora release and can drift when the base moves.
# Fedora 44 offers only JDK 25 and an early-access 27, so JDK 21 (required by the poms and used by the
# service images, eclipse-temurin-21) comes from an Eclipse Temurin tarball. The checksum is from the
# Adoptium API (api.adoptium.net), a different origin from the GitHub download.
ARG TEMURIN_RELEASE=jdk-21.0.12.1+1
ARG TEMURIN_FILE=OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz
ARG TEMURIN_SHA256=ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
ARG MAVEN_VERSION=3.9.16
ARG NODE_VERSION=v20.20.2
ARG TERRAFORM_VERSION=1.16.1
ARG MINIKUBE_VERSION=v1.38.1
ARG KUBECTL_VERSION=v1.34.1
ARG HELM_VERSION=v4.3.0
ARG AZURE_CLI_VERSION=2.91.0

# Compose provider (design D5): podman-compose is the ONLY provider. docker-compose is deliberately not
# installed: on Fedora 44 it pulls in docker-compose-switch, whose /usr/bin/docker-compose shim calls
# `docker compose` -> `podman compose` -> the shim again, a fork loop that exhausted the container's
# process limit in the spike. With one provider installed, `podman compose` needs no selection variable.
RUN dnf -y install \
        podman-docker podman-compose \
        postgresql \
        git openssl procps-ng unzip xz findutils which \
        iptables-nft conntrack-tools socat \
 && dnf clean all

# Checksums come from the same origin as the artefacts: they catch corrupted downloads, not a
# compromised release server.
RUN set -eux; cd /tmp; \
    # JDK 21 (Eclipse Temurin)
    curl -fsSLO "https://github.com/adoptium/temurin21-binaries/releases/download/$(echo "${TEMURIN_RELEASE}" | sed 's/+/%2B/')/${TEMURIN_FILE}"; \
    echo "${TEMURIN_SHA256}  ${TEMURIN_FILE}" | sha256sum -c -; \
    mkdir -p /opt/jdk-21; tar -xzf "${TEMURIN_FILE}" -C /opt/jdk-21 --strip-components=1 --no-same-owner; \
    # Maven
    curl -fsSLO "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"; \
    echo "$(curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz.sha512" | awk '{print $1}')  apache-maven-${MAVEN_VERSION}-bin.tar.gz" | sha512sum -c -; \
    tar -xzf "apache-maven-${MAVEN_VERSION}-bin.tar.gz" -C /opt; \
    ln -s "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn; \
    # Node.js
    curl -fsSLO "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz"; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" | grep " node-${NODE_VERSION}-linux-x64.tar.xz\$" | sha256sum -c -; \
    tar -xJf "node-${NODE_VERSION}-linux-x64.tar.xz" -C /usr/local --strip-components=1 --no-same-owner; \
    # Terraform
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; \
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_amd64.zip\$" | sha256sum -c -; \
    unzip -q "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" terraform -d /usr/local/bin; \
    rm -f /tmp/*.tar.gz /tmp/*.tar.xz /tmp/*.zip

ENV JAVA_HOME=/opt/jdk-21
ENV PATH="${JAVA_HOME}/bin:${PATH}"

RUN set -eux; \
    curl -fsSL -o /usr/local/bin/minikube "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64"; \
    echo "$(curl -fsSL "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64.sha256" | awk '{print $1}')  /usr/local/bin/minikube" | sha256sum -c -; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" | awk '{print $1}')  /usr/local/bin/kubectl" | sha256sum -c -; \
    curl -fsSL -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"; \
    echo "$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" | awk '{print $1}')  /tmp/helm.tgz" | sha256sum -c -; \
    tar -xzf /tmp/helm.tgz -C /tmp; mv /tmp/linux-amd64/helm /usr/local/bin/helm; rm -rf /tmp/helm.tgz /tmp/linux-amd64; \
    chmod +x /usr/local/bin/minikube /usr/local/bin/kubectl /usr/local/bin/helm

# Azure CLI from Microsoft's RPM repository (the RHEL 9 repository definition; Fedora compatibility
# is verified only by this build succeeding).
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc \
 && dnf -y install https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm \
 && dnf -y install "azure-cli-${AZURE_CLI_VERSION}" \
 && dnf clean all

COPY containers.conf /etc/containers/containers.conf
COPY registries-unqualified.conf /etc/containers/registries.conf.d/00-unqualified.conf
RUN touch /etc/containers/nodocker

# Helper commands used by the lifecycle hooks in devcontainer.json and by developers.
COPY scripts/cgroup-init.sh /usr/local/bin/devcontainer-cgroup-init
COPY scripts/minikube-start.sh /usr/local/bin/devcontainer-minikube-start
COPY scripts/healthcheck-runner.sh /usr/local/bin/devcontainer-healthcheck-runner
COPY scripts/install-playwright.sh /usr/local/bin/devcontainer-install-playwright
RUN chmod +x /usr/local/bin/devcontainer-cgroup-init /usr/local/bin/devcontainer-minikube-start /usr/local/bin/devcontainer-healthcheck-runner /usr/local/bin/devcontainer-install-playwright

WORKDIR /workspaces
