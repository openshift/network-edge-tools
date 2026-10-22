#!/usr/bin/env bash
set -euo pipefail

# NIDS Container Wrapper
# This script runs the nids-dev container with all necessary mounts and environment variables.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERFILE_CHECKSUM=$(cksum < "$SCRIPT_DIR/nids-dev.Containerfile" | awk '{print $1}')
IMAGE_NAME="nids-dev:${OCP_BIN_VERSION:-4.21.10}-${CONTAINERFILE_CHECKSUM}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
HOST_UID=$(id -u)
KRB5_HOST_PATH="${HOME}/.krb5cc_nids"

# 1. Ensure Container VM is running and clock is synced (macOS/Windows)
if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    if podman machine list 2>/dev/null | grep -qE 'applehv|qemu|wsl|hyperv'; then
        echo "==> Ensuring Podman VM is running and clock is synced..."
        podman machine start 2>/dev/null || true

        # Wait up to 10 seconds for the machine to be responsive to SSH
        PODMAN_TIME="0"
        for i in {1..10}; do
            PODMAN_TIME=$(podman machine ssh date +%s 2>/dev/null || echo "0")
            if [[ "$PODMAN_TIME" -gt 0 ]]; then break; fi
            sleep 1
        done

        if [[ "$PODMAN_TIME" -gt 0 ]]; then
            HOST_TIME=$(date +%s)
            DIFF=$(( HOST_TIME - PODMAN_TIME ))
            DIFF=${DIFF#-} # absolute value
            if (( DIFF > 2 )); then
                echo "    Syncing Podman VM clock (drift: ${DIFF}s)..."
                podman machine ssh sudo date -s "@$HOST_TIME" >/dev/null 2>&1 || true
            fi
        else
            echo "    WARNING: Podman VM did not respond to SSH. Clock sync skipped."
        fi
    fi
fi

# 1.5. Host Clock Sanity Check
# If the host clock is wildly off, AWS and TLS will fail even if the container matches the host.
echo "==> Performing host clock sanity check..."
HTTP_DATE=$(curl -sI --connect-timeout 2 https://google.com | grep -i "^date:" | sed 's/Date: //i' || echo "")
if [[ -n "$HTTP_DATE" ]]; then
    NETWORK_TIME=$(python3 -c "import email.utils; print(int(email.utils.mktime_tz(email.utils.parsedate_tz('''$HTTP_DATE'''))))" 2>/dev/null || echo "0")
    if [[ "$NETWORK_TIME" -gt 0 ]]; then
        HOST_TIME=$(date +%s)
        HOST_DRIFT=$(( HOST_TIME - NETWORK_TIME ))
        HOST_DRIFT=${HOST_DRIFT#-}
        if (( HOST_DRIFT > 30 )); then
            echo "************************************************************************"
            echo " CRITICAL WARNING: YOUR HOST CLOCK IS OUT OF SYNC (Drift: ${HOST_DRIFT}s)"
            echo " This will cause AWS Auth failures and TLS certificate errors."
            echo " Please ensure your system time is set to update automatically."
            echo "************************************************************************"
            sleep 2
        else
            echo "    Host clock is sane (drift: ${HOST_DRIFT}s)."
        fi
    fi
fi

# 2. Ensure the container image exists
# We use både 'image exists' (podman) and 'inspect' (docker/podman) for compatibility
if ! "$CONTAINER_ENGINE" inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "==> Container image $IMAGE_NAME not found. Building..."
    "$CONTAINER_ENGINE" build -t "$IMAGE_NAME" -t nids-dev:latest \
        ${OCP_MIRROR_PATH:+--build-arg "OCP_MIRROR_PATH=${OCP_MIRROR_PATH}"} \
        ${OCP_BIN_VERSION:+--build-arg "OCP_BIN_VERSION=${OCP_BIN_VERSION}"} \
        -f "$SCRIPT_DIR/nids-dev.Containerfile" "$SCRIPT_DIR"
fi

# 3. Ensure Kerberos ticket is available in FILE format on host
# Macs and some Linux distros use non-file caches (API/KCM) by default.
# We must ensure a FILE-based cache exists for mounting into the container.
KINIT_OPTS=""
# Optional: look for a password file in project root or home to skip prompt
PASSWD_FILE="${PWD}/.krb-passwd"
[[ ! -f "$PASSWD_FILE" ]] && PASSWD_FILE="${HOME}/.krb-passwd"

if [[ -f "$PASSWD_FILE" ]]; then
    echo "    Using Kerberos password file: $PASSWD_FILE"
    KINIT_OPTS="--password-file=$PASSWD_FILE"
fi

echo "==> Ensuring Kerberos ticket is available in $KRB5_HOST_PATH..."
if ! KRB5CCNAME="FILE:${KRB5_HOST_PATH}" klist -s 2>/dev/null; then
    echo "    Refreshing file-based ticket cache..."
    # We use -c explicitly to force writing to the file cache
    kinit -c "FILE:${KRB5_HOST_PATH}" $KINIT_OPTS "${KERBEROS_ID:-${USER}}@IPA.REDHAT.COM" || exit 1
fi

if [[ -d "$HOME/.aws-saml-venv" && -f "$SCRIPT_DIR/redhat-aws.sh" ]]; then
    echo "    Pre-fetching AWS credentials on host to cache service ticket..."
    (
        export FRESH_SESSION=true
        export PROFILE="${AWS_PROFILE:-nids-dev}"
        export VENV_PATH="${HOME}/.aws-saml-venv"
        export KRB5CCNAME="FILE:${KRB5_HOST_PATH}"
        source "$SCRIPT_DIR/redhat-aws.sh"
    ) || echo "    WARNING: Host AWS refresh failed. Container will attempt it."
fi

# 4. Run the container

# Linux-specific fixes for SELinux and file permissions
EXTRA_FLAGS=""
SELINUX_SUFFIX=""
if [[ "$(uname)" == "Linux" ]]; then
    # :z is a safe no-op on non-SELinux systems, but essential for Fedora/RHEL
    SELINUX_SUFFIX=",z"
    if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
        # Map host UID to container UID. Standard for Linux Podman.
        EXTRA_FLAGS="--userns=keep-id"
    else
        # For Docker on Linux, we run as the current user to fix host file ownership
        EXTRA_FLAGS="--user $(id -u):$(id -g)"
    fi
fi

SYNC_PID=""
if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    if podman machine list 2>/dev/null | grep -qE 'applehv|qemu|wsl|hyperv'; then
        # Start a background clock sync loop to prevent AuthFailures during long waits
        (
            while true; do
                sleep 60
                HOST_TIME=$(date +%s)
                podman machine ssh sudo date -s "@$HOST_TIME" >/dev/null 2>&1 || true
            done
        ) &
        SYNC_PID=$!
    fi
fi

"$CONTAINER_ENGINE" run -it --rm \
    $EXTRA_FLAGS \
    --name nids-dev-shell \
    -v "$(pwd):/workspace:z" \
    -v "$HOME/.aws:/home/developer/.aws:z" \
    -v "$HOME/.ssh:/home/developer/.ssh:ro${SELINUX_SUFFIX}" \
    -v "$HOME/.ocp-installer-pull-secret:/home/developer/.ocp-installer-pull-secret:ro${SELINUX_SUFFIX}" \
    -v "${KRB5_HOST_PATH}:/tmp/krb5cc_1000:ro${SELINUX_SUFFIX}" \
    -e NIDS_CONTAINER="true" \
    -e USER="${USER:-}" \
    -e AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}" \
    -e KERBEROS_ID="${KERBEROS_ID:-$USER}" \
    -e OCP_BASE_DOMAIN="${OCP_BASE_DOMAIN:-}" \
    -e OCP_REGION="${OCP_REGION:-}" \
    "$IMAGE_NAME" "$@"

if [[ -n "$SYNC_PID" ]]; then
    kill "$SYNC_PID" 2>/dev/null || true
fi
