#!/usr/bin/env bash
set -euo pipefail

# --- Container Auto-Detection ---
# If we are NOT in the container, re-exec via nids-run.sh
if [[ ! -f /run/.containerenv && "${NIDS_CONTAINER:-}" != "true" ]]; then
    echo "==> Host execution detected. Re-launching inside nids-dev container..."
    # We use ./basename to ensure the container looks in /workspace
    exec "$(dirname "$0")/nids-run.sh" "./$(basename "$0")" "$@"
fi

# --- settings (matching ocp-cluster-one-shot.sh defaults) ---
OCP_ASSET_DIR="${OCP_ASSET_DIR:-$(pwd)/ocp-install-dir}"
AWS_ENV_SCRIPT="${AWS_ENV_SCRIPT:-$(dirname "$0")/redhat-aws.sh}"

die() { echo "ERROR: $*" >&2; exit 1; }

# sanity checks
command -v aws >/dev/null 2>&1 || die "aws cli not found in PATH"
command -v openshift-install >/dev/null 2>&1 || die "openshift-install not found in PATH (are you in the container?)"
[[ -f "$AWS_ENV_SCRIPT" ]] || die "aws env script not found at $AWS_ENV_SCRIPT"

# 1) source AWS profile setup
# shellcheck source=/dev/null
export FRESH_SESSION="${FRESH_SESSION:-false}"
source "$AWS_ENV_SCRIPT"

if [[ ! -d "$OCP_ASSET_DIR" ]]; then
    echo "Asset directory $OCP_ASSET_DIR not found. Nothing to destroy."
    exit 0
fi

echo "==> destroying cluster in $OCP_ASSET_DIR using openshift-install"
openshift-install destroy cluster --dir "$OCP_ASSET_DIR" --log-level=info

echo "==> cleanup asset dir"
rm -rf "$OCP_ASSET_DIR"
echo "Done."
