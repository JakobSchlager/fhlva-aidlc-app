# Throwaway spike image for add-podman-devcontainer. NOT the final devcontainer image.
# Mirrors "candidate A" from the Linux spike, with the fixes it found baked in
# (host-namespace containers.conf replaced, openssl and ps added, short-name registry).
FROM quay.io/podman/stable:latest
USER root

RUN dnf -y install podman-docker docker-compose podman-compose openssl procps-ng git \
        iptables-nft conntrack-tools socat \
 && dnf clean all

# Tool versions used in the Linux spike. Linux x86-64 binaries; URLs follow each project's
# release pattern and are verified only by this image building successfully.
ARG MINIKUBE_VERSION=v1.38.1
ARG KUBECTL_VERSION=v1.34.1
ARG HELM_VERSION=v4.3.0
RUN curl -fsSL -o /usr/local/bin/minikube "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64" \
 && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C /tmp \
 && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
 && chmod +x /usr/local/bin/minikube /usr/local/bin/kubectl /usr/local/bin/helm

# The base image forces host namespaces and disables cgroups, which breaks minikube's node container.
COPY containers.conf /etc/containers/containers.conf
COPY registries-unqualified.conf /etc/containers/registries.conf.d/00-unqualified.conf
RUN touch /etc/containers/nodocker

COPY spike-init.sh spike-prepare.sh spike-minikube.sh spike-deploy.sh spike-probe.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/spike-*.sh
