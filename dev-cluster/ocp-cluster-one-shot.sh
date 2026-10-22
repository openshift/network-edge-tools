#!/usr/bin/env bash
set -euo pipefail

# --- Container Auto-Detection ---
# If we are NOT in the container, re-exec via nids-run.sh
if [[ ! -f /run/.containerenv && "${NIDS_CONTAINER:-}" != "true" ]]; then
    echo "==> Host execution detected."
    OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-nids-dev.devcluster.openshift.com}"
    KNOWN_NS_IP="205.251.196.100"

    # Configure Host Split DNS to bypass broken parent delegation
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ ! -f "/etc/resolver/$OCP_BASE_DOMAIN" ]]; then
            echo "==> Applying macOS split DNS to fix devcluster resolution. (Requires sudo)"
            sudo mkdir -p /etc/resolver
            echo "nameserver $KNOWN_NS_IP" | sudo tee "/etc/resolver/$OCP_BASE_DOMAIN" >/dev/null
        fi
    elif [[ "$(uname)" == "Linux" ]]; then
        if command -v resolvectl >/dev/null 2>&1; then
            if ! resolvectl status 2>/dev/null | grep -q "$OCP_BASE_DOMAIN"; then
                echo "==> Applying systemd-resolved split DNS to fix devcluster resolution. (Requires sudo)"
                sudo mkdir -p /etc/systemd/resolved.conf.d
                cat <<EOF | sudo tee "/etc/systemd/resolved.conf.d/$OCP_BASE_DOMAIN.conf" >/dev/null
[Resolve]
DNS=$KNOWN_NS_IP
Domains=~$OCP_BASE_DOMAIN
EOF
                sudo systemctl restart systemd-resolved
            fi
        fi
    fi

    # Set container build args based on requested version
    HOST_OCP_VERSION="${1:-4.21}"
    case "$HOST_OCP_VERSION" in
        4.19)
            export OCP_MIRROR_PATH=ocp/4.19.12
            export OCP_BIN_VERSION=4.19.12
            ;;
        4.21)
            export OCP_MIRROR_PATH=ocp/4.21.10
            export OCP_BIN_VERSION=4.21.10
            ;;
        5.0)
            export OCP_MIRROR_PATH=ocp-dev-preview/candidate-5.0
            export OCP_BIN_VERSION=5.0.0-ec.3
            ;;
        *)
            if [[ "$HOST_OCP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                export OCP_MIRROR_PATH="ocp/$HOST_OCP_VERSION"
                export OCP_BIN_VERSION="$HOST_OCP_VERSION"
            fi
            ;;
    esac

    echo "==> Re-launching inside nids-dev container..."
    # We use ./basename to ensure the container looks in /workspace
    exec "$(dirname "$0")/nids-run.sh" "./$(basename "$0")" "$@"
fi

# --- Version Selection ---
# Default to 4.21 if no version is provided
OCP_VERSION="${1:-4.21}"
# Shift so any other potential args are preserved (though not currently used)
[[ $# -gt 0 ]] && shift

case "$OCP_VERSION" in
    4.19)
        RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.19.12-x86_64"
        ;;
    4.21)
        RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.21.10-x86_64"
        ;;
    5.0)
        RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:5.0.0-ec.3-x86_64"
        ;;
    *)
        # Handle full versions like 4.21.10
        if [[ "$OCP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
             RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:${OCP_VERSION}-x86_64"
        else
             echo "ERROR: Unsupported version: $OCP_VERSION. Use '4.19', '4.21', or a full tag like '4.21.10'." >&2
             exit 1
        fi
        ;;
esac

echo "==> Preparing to deploy OpenShift $OCP_VERSION using payload: $RELEASE_IMAGE"

# --- user-tunable settings (use OCP_* to avoid clashes with AWS_* cleanup) ---
OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-nids-dev.devcluster.openshift.com}"
OCP_REGION="${OCP_REGION:-us-west-2}"
OCP_ASSET_DIR="${OCP_ASSET_DIR:-$(pwd)/ocp-install-dir}"

# Ensure unique sequential name
COUNTER_FILE="/workspace/.ocp_cluster_counter"
if [[ ! -f "$COUNTER_FILE" ]]; then
    echo "1" > "$COUNTER_FILE"
fi
COUNTER=$(cat "$COUNTER_FILE")
echo "$((COUNTER + 1))" > "$COUNTER_FILE"

# Limit name to 21 chars: USER(max 8) + - + date(6) + - + counter
SAFE_USER=$(echo "$USER" | cut -c 1-8)
CURRENT_DATE=$(date +%y%m%d)
OCP_CLUSTER_NAME="${OCP_CLUSTER_NAME:-${SAFE_USER}-${CURRENT_DATE}-${COUNTER}}"

# 0) prep asset dir (clean slate)
if [[ -f "$OCP_ASSET_DIR/metadata.json" ]]; then
    echo "==> Found existing cluster metadata in $OCP_ASSET_DIR."
    echo "==> Running automated teardown to prevent orphaned AWS resources..."
    "$(dirname "$0")/ocp-cluster-teardown.sh" || echo "    [WARNING] Teardown returned an error, proceeding with clean slate anyway..."
fi
rm -rf "$OCP_ASSET_DIR"
mkdir -p "$OCP_ASSET_DIR"

# secrets/keys
# In container, HOME is /home/developer
PULL_SECRET_PATH="${PULL_SECRET_PATH:-$HOME/.ocp-installer-pull-secret}"
SSH_PUBKEY_PATH="${SSH_PUBKEY_PATH:-$HOME/.ssh/id_ed25519.pub}"

# aws environment bootstrapper
AWS_ENV_SCRIPT="${AWS_ENV_SCRIPT:-$(dirname "$0")/redhat-aws.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }

# sanity checks
command -v aws >/dev/null 2>&1 || die "aws cli not found in PATH"
command -v openshift-install >/dev/null 2>&1 || die "openshift-install not found in PATH (are you in the container?)"
[[ -f "$AWS_ENV_SCRIPT" ]] || die "aws env script not found at $AWS_ENV_SCRIPT"
[[ -f "$PULL_SECRET_PATH" ]] || die "pull secret not found at $PULL_SECRET_PATH"
[[ -f "$SSH_PUBKEY_PATH" ]] || die "ssh public key not found at $SSH_PUBKEY_PATH"

# 1) source AWS profile setup
# shellcheck source=/dev/null
export FRESH_SESSION="${FRESH_SESSION:-false}"
source "$AWS_ENV_SCRIPT"

# Force x86_64 release payload (prevents ARM64 installer from defaulting to Graviton)
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="$RELEASE_IMAGE"

echo "==> verifying aws profile in use"
aws configure list || die "failed to read aws configuration"
echo "==> identity check"
aws sts get-caller-identity || die "failed to get caller identity"

# 1.5) AWS Networking Sanity Check (Idempotency fixes)
echo "==> performing aws networking sanity checks"

# A) VPC Block Public Access (Fixes the "horribly wrong" account-level block)
BPA_MODE=$(aws ec2 describe-vpc-block-public-access-options --query 'VpcBlockPublicAccessOptions.InternetGatewayBlockMode' --output text 2>/dev/null || echo "off")
if [[ "$BPA_MODE" != "off" ]]; then
    echo "WARNING: VPC Block Public Access is set to '$BPA_MODE' in $OCP_REGION."
    echo "==> attempting to disable VPC Block Public Access (idempotent fix)..."
    aws ec2 modify-vpc-block-public-access-options --internet-gateway-block-mode off || echo "WARNING: failed to disable BPA (might lack permissions), install may fail."
else
    echo "OK: VPC Block Public Access is off."
fi

# B) Route53 Record Limit Check
ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$OCP_BASE_DOMAIN" --query 'HostedZones[0].Id' --output text 2>/dev/null || echo "None")
if [[ "$ZONE_ID" != "None" && "$ZONE_ID" != "null" ]]; then
    RECORD_COUNT=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query 'length(ResourceRecordSets)' 2>/dev/null || echo "0")
    echo "INFO: Route53 records in $OCP_BASE_DOMAIN: $RECORD_COUNT"
    if (( RECORD_COUNT > 9800 )); then
        echo "CRITICAL WARNING: Route53 record count is at $RECORD_COUNT (Limit 10,000). Delete old clusters!"
    fi

    # Inject authoritative NS into container DNS to completely bypass broken public parent delegation
    MY_NS=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query "ResourceRecordSets[?Type=='NS'].ResourceRecords[0].Value" --output text 2>/dev/null | head -n1)
    if [[ -n "$MY_NS" ]]; then
        MY_NS_IP=$(python3 -c "import socket, sys; print(socket.gethostbyname(sys.argv[1].rstrip('.')))" "$MY_NS" 2>/dev/null || echo "")
        if [[ -n "$MY_NS_IP" ]]; then
            echo "==> Configuring dnsmasq to bypass broken parent delegation for $OCP_BASE_DOMAIN..."
            command -v sudo >/dev/null 2>&1 || die "sudo is missing from the container image; rebuild it with ./nids-run.sh"
            command -v dnsmasq >/dev/null 2>&1 || die "dnsmasq is missing from the container image; rebuild it with ./nids-run.sh"
            grep nameserver /etc/resolv.conf | grep -v "127.0.0.1" | sudo tee /etc/resolv.dnsmasq >/dev/null
            cat <<EOF | sudo tee /etc/dnsmasq.conf >/dev/null
resolv-file=/etc/resolv.dnsmasq
server=/$OCP_BASE_DOMAIN/$MY_NS_IP
listen-address=127.0.0.1
bind-interfaces
EOF
            sudo pkill dnsmasq 2>/dev/null || true
            sudo dnsmasq
            echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null
        fi
    fi
else
    echo "WARNING: Could not find Route53 zone for $OCP_BASE_DOMAIN. DNS verification may fail."
fi

# 3) compose install-config.yaml
PULL_SECRET_CONTENT="$(cat "$PULL_SECRET_PATH")"
SSH_PUBKEY_CONTENT="$(cat "$SSH_PUBKEY_PATH")"

cat > "$OCP_ASSET_DIR/install-config.yaml" <<'YAML'
apiVersion: v1
baseDomain: __BASE_DOMAIN__
metadata:
  name: __CLUSTER_NAME__
platform:
  aws:
    region: __REGION__
controlPlane:
  architecture: amd64
compute:
- name: worker
  replicas: 3
  architecture: amd64
credentialsMode: Manual
pullSecret: '__PULL_SECRET__'
sshKey: '__SSH_PUBKEY__'
YAML

# 4) safe placeholder substitution (handles quotes/newlines)
python3 - "$OCP_ASSET_DIR/install-config.yaml" <<PY
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
replacements = {
    "__BASE_DOMAIN__": """$OCP_BASE_DOMAIN""",
    "__CLUSTER_NAME__": """$OCP_CLUSTER_NAME""",
    "__REGION__": """$OCP_REGION""",
    "__PULL_SECRET__": """$PULL_SECRET_CONTENT""",
    "__SSH_PUBKEY__": """$SSH_PUBKEY_CONTENT""",
}
for k,v in replacements.items():
    s = s.replace(k, v)
p.write_text(s)
PY

# keep a backup (installer consumes install-config.yaml)
cp "$OCP_ASSET_DIR/install-config.yaml" "$OCP_ASSET_DIR/install-config.backup.yaml"

echo "==> 1. Generating OpenShift Keys via ccoctl first..."
mkdir -p "$OCP_ASSET_DIR/ccoctl-keys"

# Call ccoctl directly (it's in the image)
ccoctl aws create-key-pair --output-dir="$OCP_ASSET_DIR/ccoctl-keys" || die "failed to generate ccoctl keys"

# The installer MUST have this file present BEFORE create manifests runs
mkdir -p "$OCP_ASSET_DIR/tls"
cp "$OCP_ASSET_DIR/ccoctl-keys/serviceaccount-signer.private" "$OCP_ASSET_DIR/tls/bound-service-account-signing-key.key"

echo "==> 2. creating manifests (phase 1) in $OCP_ASSET_DIR"
openshift-install create manifests --dir "$OCP_ASSET_DIR" --log-level=info

echo "==> 3. extracting CredentialsRequest manifests for ccoctl"
CRED_REQ_DIR="$OCP_ASSET_DIR/credrequests"
mkdir -p "$CRED_REQ_DIR"

# Extract CredentialsRequests using the oc CLI (already in the image)
oc adm release extract \
    --credentials-requests \
    --cloud=aws \
    --to="$CRED_REQ_DIR" \
    "$RELEASE_IMAGE" || die "failed to extract credrequests via oc adm"

# Check if we actually found any cred requests
if [ -z "$(ls -A "$CRED_REQ_DIR" 2>/dev/null)" ]; then
    echo "WARNING: No CredentialsRequest files found. This is unusual but we will try to proceed."
else
    echo "==> 4. provisioning AWS IAM roles with ccoctl"

    # In the container, the environment variables are already set by redhat-aws.sh
    ccoctl aws create-all \
        --name="$OCP_CLUSTER_NAME" \
        --region="$OCP_REGION" \
        --credentials-requests-dir="$CRED_REQ_DIR" \
        --public-key-file="$OCP_ASSET_DIR/ccoctl-keys/serviceaccount-signer.public" \
        --output-dir="$OCP_ASSET_DIR/ccoctl-output" || die "ccoctl provisioning failed"

    echo "==> 5. injecting ccoctl manifests into installer asset dir"
    cp -r "$OCP_ASSET_DIR/ccoctl-output/manifests/"* "$OCP_ASSET_DIR/manifests/" || die "failed to inject ccoctl manifests"
    cp -r "$OCP_ASSET_DIR/ccoctl-output/tls/"* "$OCP_ASSET_DIR/tls/" 2>/dev/null || true # Optional tls dir

    echo "==> fixing IAM OIDC Thumbprint (AWS Root CA mismatch)"
    S3_HOST="${OCP_CLUSTER_NAME}-oidc.s3.${OCP_REGION}.amazonaws.com"
    OIDC_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE"):oidc-provider/${S3_HOST}"

    echo "    Ensuring OIDC files have correct Content-Type in S3..."
    aws s3 cp "s3://${OCP_CLUSTER_NAME}-oidc/.well-known/openid-configuration" "s3://${OCP_CLUSTER_NAME}-oidc/.well-known/openid-configuration" --content-type "application/json" --metadata-directive REPLACE --profile "$AWS_PROFILE" >/dev/null 2>&1
    aws s3 cp "s3://${OCP_CLUSTER_NAME}-oidc/keys.json" "s3://${OCP_CLUSTER_NAME}-oidc/keys.json" --content-type "application/json" --metadata-directive REPLACE --profile "$AWS_PROFILE" >/dev/null 2>&1

    echo "    Fetching root certificate for $S3_HOST..."
    ACTUAL_THUMBPRINT=$(echo -n | openssl s_client -connect "${S3_HOST}:443" -showcerts 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print}' | awk -v RS="-----END CERTIFICATE-----" 'NR==2 {print $0 RS}' | openssl x509 -fingerprint -noout -sha1 2>/dev/null | sed 's/.*=//' | tr -d ':' | tr '[:upper:]' '[:lower:]')

    if [[ -n "$ACTUAL_THUMBPRINT" ]]; then
        echo "    Updating OIDC provider with thumbprint list including: $ACTUAL_THUMBPRINT"
        aws iam update-open-id-connect-provider-thumbprint \
            --open-id-connect-provider-arn "$OIDC_ARN" \
            --thumbprint-list "06b25927c42a721631c1efd9431e648fa62e1e39" "8da7f965ec5efc37910f1c6e59fdc1cc6a6ede16" "$ACTUAL_THUMBPRINT" \
            --profile "$AWS_PROFILE" >/dev/null 2>&1 || echo "    WARNING: Failed to update OIDC thumbprint. Cluster may fail to boot."
    else
        echo "    WARNING: Could not fetch certificate fingerprint. Cluster may fail to boot."
    fi
fi

echo "==> 6. creating ignition configs (phase 2) in $OCP_ASSET_DIR"
openshift-install create ignition-configs --dir "$OCP_ASSET_DIR" --log-level=info

echo "==> launching openshift-install create cluster (phase 3) with dir=$OCP_ASSET_DIR"
openshift-install create cluster --dir "$OCP_ASSET_DIR" --log-level=info
