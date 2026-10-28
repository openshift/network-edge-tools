> Historical notes imported from `bentito/selfhelp` at `9f12e1c`.
> The paths, cluster status, and plans below describe that earlier work.
> See the [current setup guide](../../README.md) for usage.

# Cluster One-Shot Progress & Handoff

## Project Overview
Automate OpenShift (4.19 / 4.21) deployments on AWS using a "one-shot" script on macOS (ARM64). This requires using Podman to execute Linux-specific binaries like `ccoctl` and managing STS/SAML-based authentication.

## Trigger for Rework
Migration from a legacy AWS account to the `nids-dev` account (ID: 472353357491). This new account enforces:
- SAML authentication via `aws-saml.py`.
- Manual credentials mode in the installer (using STS/OIDC).
- Strict OIDC provider requirements for cluster operators.

## Current Workspace State
- **Active Install Directory:** `/Users/btofel/workspace/selfhelp/ocp-install-dir/`
- **Active Cluster:** `btofel-260519-21` (Deployment in progress).
- **Recent Fixes:**
  - **EIP Limit Resolved:** Cleaned up leaked Elastic IPs from orphaned clusters (`260518-3`, etc.).
  - **OIDC Thumbprint Enhanced:** The one-shot script now includes a broader set of thumbprints (including the self-signed Amazon Root CA 1) for STS compatibility.
  - **S3 Metadata Fix:** Forced `Content-Type: application/json` on OIDC discovery files in S3.
- **Available Logs:**
  - Deployment log: `ocp-install-dir/.openshift_install.log`
  - Kubeconfig: `ocp-install-dir/auth/kubeconfig`
  - Forensic data: `image-registry` operator logs show persistent `InvalidIdentityToken: Couldn't retrieve verification key`.

## Technical Modifications Completed
The following fixes have been implemented and verified in the `ocp-cluster-one-shot-*.sh` scripts:
1.  **Podman Integration:** `ccoctl` (Linux arm64) runs via a container with necessary CA certificates to reach AWS APIs.
2.  **SAML Session Extension:** `redhat-aws.sh` now requests a 12-hour duration (`--session-duration 43200`) to prevent credential expiry during the 45-minute install.
3.  **OIDC Thumbprint Patching:** The script dynamically fetches the S3 certificate chain and patches the IAM OIDC Provider with the **Amazon Root CA 1** thumbprint (`2ad974...`), which is required by STS in `us-west-2`.
4.  **Key Synchronization:** Reordered the workflow to ensure the OpenShift cluster and S3 OIDC bucket use identical RSA keys:
    - Generate keys via `ccoctl aws create-key-pair`.
    - Inject the private key into the installer's `tls/` directory *before* manifest generation.
    - Pass the matching public key to `ccoctl aws create-all`.
5.  **Route53 Recovery:** Fixed a deleted hosted zone and verified global DNS delegation is functional.

## Unresolved Blockers
The most recent deployment (`260519-18`) failed during initialization.
- **The Symptom:** The `image-registry` operator reports `InvalidIdentityToken: Couldn't retrieve verification key`.
- **The Paradox:** A local verification script (`test_crypto_sync.sh`) using the same RSA keys and targeting the same IAM role **succeeds** in assuming the role from the laptop environment.
- **Hypothesis:** There is a discrepancy between the JWT tokens issued by the Kubernetes API-server within the cluster and the manually signed tokens used in our local test. This may involve:
  - `iss` (Issuer) URL mismatches (e.g., presence/absence of trailing slashes).
  - `aud` (Audience) claim mismatches.
  - Potential issues with how the installer configures the `serviceAccountIssuer` in the cluster-authentication manifests.

## Files for Reference
- `ocp-cluster-one-shot-4.21.sh`: Main deployment logic.
- `redhat-aws.sh`: AWS environment/auth helper.
- `test_crypto_sync.sh`: Diagnostic script that successfully validates STS trust for a given keypair.
- `vpc-test.sh`: Diagnostic script that verified VPC outbound reachability.
- `ocp-cluster-teardown.sh`: Cleanup script.
