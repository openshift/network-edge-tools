#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking prerequisites for NIDS AWS Deployment..."

# 1. Check VPN/Network (Can we reach internal GitLab?)
if ! curl -I -s --connect-timeout 5 https://gitlab.cee.redhat.com >/dev/null; then
    echo "WARNING: Cannot reach gitlab.cee.redhat.com."
    echo "         Please ensure you are connected to the Red Hat GlobalProtect VPN."
    echo "         The installation of internal tools will likely fail."
    echo ""
fi

# 2. Check System Dependencies (kinit)
if ! command -v kinit >/dev/null 2>&1; then
    echo "WARNING: 'kinit' not found on your system."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "         Mac Users: You may need to run: brew install krb5"
    else
        echo "         Linux Users: You may need to run: sudo dnf install krb5-devel python3-devel openldap-devel"
    fi
    echo ""
fi

# 3. Check Required Files
if [[ ! -f "$HOME/.ocp-installer-pull-secret" ]]; then
    echo "WARNING: Missing OpenShift Pull Secret at $HOME/.ocp-installer-pull-secret"
    echo "         Download it from: https://console.redhat.com/openshift/install/pull-secret"
    echo ""
fi

if [[ ! -f "$HOME/.ssh/id_ed25519.pub" && ! -f "$HOME/.ssh/id_rsa.pub" ]]; then
    echo "WARNING: No default SSH public key found in $HOME/.ssh/"
    echo "         You may need to run: ssh-keygen -t ed25519"
    echo ""
fi

# 4. Build Container Image
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERFILE_CHECKSUM=$(cksum < "$SCRIPT_DIR/nids-dev.Containerfile" | awk '{print $1}')
IMAGE_NAME="nids-dev:4.21.10-${CONTAINERFILE_CHECKSUM}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

echo "==> Building container image $IMAGE_NAME using $CONTAINER_ENGINE..."
echo "    (Note: This is also handled automatically by the one-shot scripts)"

if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
    echo "ERROR: '$CONTAINER_ENGINE' not found. Please install it first or set CONTAINER_ENGINE."
    exit 1
fi

# Detect platform for native build
if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    PLATFORM="linux/$(podman info --format '{{.Host.Arch}}')"
else
    # Docker uses slightly different naming or we can just let it default to native
    PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
fi

"$CONTAINER_ENGINE" build --platform "$PLATFORM" -t "$IMAGE_NAME" -t nids-dev:latest -f "$SCRIPT_DIR/nids-dev.Containerfile" "$SCRIPT_DIR"

echo "------------------------------------------------------------"
echo "==> Setup Complete!"
echo "The NIDS development environment is containerized."
echo ""
echo "You can now run the deployment script directly from your host:"
echo "    ./ocp-cluster-one-shot.sh"
echo ""
echo "Everything (Kerberos, Image Build, AWS SAML) is handled automatically."
echo "------------------------------------------------------------"
