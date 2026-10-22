#!/usr/bin/env bash
set -euo pipefail

# Build from the host so corporate split DNS can be passed to the container.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
CONTAINERFILE_CHECKSUM=$(cksum < "$SCRIPT_DIR/nids-dev.Containerfile" | awk '{print $1}')
OCP_BIN_VERSION="${OCP_BIN_VERSION:-4.21.10}"
OCP_MIRROR_PATH="${OCP_MIRROR_PATH:-ocp/$OCP_BIN_VERSION}"
IMAGE_NAME="nids-dev:${OCP_BIN_VERSION}-${CONTAINERFILE_CHECKSUM}"
GITLAB_HOST="gitlab.cee.redhat.com"

if ! GITLAB_IP=$(python3 - "$GITLAB_HOST" <<'PY'
import socket
import sys

try:
    print(socket.gethostbyname(sys.argv[1]))
except OSError:
    sys.exit(1)
PY
); then
    echo "ERROR: Cannot resolve $GITLAB_HOST from the host." >&2
    echo "Connect to the Red Hat corporate VPN, then rerun the command." >&2
    exit 1
fi

if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    PLATFORM="linux/$(podman info --format '{{.Host.Arch}}')"
else
    PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
fi

echo "==> Building $IMAGE_NAME for $PLATFORM using $CONTAINER_ENGINE..."
# The container VM may not inherit the host's corporate split DNS resolver.
# This mapping applies only to the build and is refreshed on each invocation.
exec "$CONTAINER_ENGINE" build --platform "$PLATFORM" \
    --add-host "${GITLAB_HOST}:${GITLAB_IP}" \
    -t "$IMAGE_NAME" -t nids-dev:latest \
    --build-arg "OCP_MIRROR_PATH=$OCP_MIRROR_PATH" \
    --build-arg "OCP_BIN_VERSION=$OCP_BIN_VERSION" \
    -f "$SCRIPT_DIR/nids-dev.Containerfile" "$SCRIPT_DIR"
