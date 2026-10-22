# Use RHEL 9 UBI as the base
FROM registry.access.redhat.com/ubi9/ubi:latest

# Install system dependencies
RUN dnf install -y \
    krb5-workstation \
    krb5-devel \
    openldap-devel \
    python3-devel \
    gcc \
    git \
    openssh-clients \
    python3-pip \
    tar \
    gzip \
    unzip \
    bind-utils \
    dnsmasq \
    sudo \
    && dnf clean all

# Install AWS CLI v2 dynamically based on architecture
RUN HOST_ARCH=$(uname -m) && \
    if [ "$HOST_ARCH" == "aarch64" ]; then \
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"; \
    else \
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"; \
    fi && \
    curl "$AWS_URL" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip ./aws

# Install OpenShift Binaries (oc, openshift-install, ccoctl)
ARG OCP_MIRROR_PATH=ocp/4.21.10
ARG OCP_BIN_VERSION=4.21.10
RUN HOST_ARCH=$(uname -m) && \
    if [ "$HOST_ARCH" == "aarch64" ]; then MIRROR_ARCH="aarch64"; else MIRROR_ARCH="x86_64"; fi && \
    mkdir -p /usr/local/bin && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/${MIRROR_ARCH}/clients/${OCP_MIRROR_PATH}/openshift-install-linux-${OCP_BIN_VERSION}.tar.gz | tar -xz -C /usr/local/bin openshift-install && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/${MIRROR_ARCH}/clients/${OCP_MIRROR_PATH}/openshift-client-linux-${OCP_BIN_VERSION}.tar.gz | tar -xz -C /usr/local/bin oc && \
    curl -L https://mirror.openshift.com/pub/openshift-v4/${MIRROR_ARCH}/clients/${OCP_MIRROR_PATH}/ccoctl-linux-${OCP_BIN_VERSION}.tar.gz | tar -xz -C /usr/local/bin ccoctl

# Install internal Red Hat SAML tool
# We use the same GIT_SSL_NO_VERIFY trick as the setup.sh
RUN GIT_SSL_NO_VERIFY=true pip install --no-cache-dir git+https://gitlab.cee.redhat.com/compute/aws-automation.git

# Setup developer user
RUN useradd -u 1000 -m developer && \
    echo "developer ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
USER developer
WORKDIR /workspace

# Kerberos and AWS environment
ENV KRB5CCNAME=FILE:/tmp/krb5cc_1000
ENV PATH="/home/developer/.local/bin:${PATH}"

# Default command
CMD ["/bin/bash"]
