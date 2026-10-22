#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking prerequisites for NIDS AWS Deployment..."

# 1. Check System Dependencies (kinit)
if ! command -v kinit >/dev/null 2>&1; then
    echo "WARNING: 'kinit' not found on your system."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "         Mac Users: You may need to run: brew install krb5"
    else
        echo "         Linux Users: You may need to run: sudo dnf install krb5-devel python3-devel openldap-devel"
    fi
    echo ""
fi

# 2. Check Required Files
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

# 3. Build Container Image (checks VPN DNS before downloading dependencies)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

echo "    (Note: This is also handled automatically by the one-shot scripts)"

if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
    echo "ERROR: '$CONTAINER_ENGINE' not found. Please install it first or set CONTAINER_ENGINE."
    exit 1
fi

"$SCRIPT_DIR/nids-build.sh"

echo "------------------------------------------------------------"
echo "==> Setup Complete!"
echo "The NIDS development environment is containerized."
echo ""
echo "You can now run the deployment script directly from your host:"
echo "    ./ocp-cluster-one-shot.sh"
echo ""
echo "Everything (Kerberos, Image Build, AWS SAML) is handled automatically."
echo "------------------------------------------------------------"
