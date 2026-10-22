> Historical notes imported from `bentito/selfhelp` at `9f12e1c`.
> The paths, cluster status, and plans below describe that earlier work.
> See the [current setup guide](../../README.md) for usage.

# NIDS Containerization Revision Plan

Goal: Streamline the NIDS cluster deployment process by moving all dependencies (Python, AWS SAML, OpenShift binaries) into a Podman container. This eliminates the need for local Python virtual environments and complex system dependencies on the host.

## Phase 1: Container Image Construction
- **Base Image:** RHEL UBI 9 (`registry.access.redhat.com/ubi9/ubi:latest`).
- **Tools Included:**
  - `awscli` (via dnf or pip)
  - `krb5-workstation` (for SAML interaction)
  - `oc` and `openshift-install` (Linux x86_64 binaries)
  - `ccoctl` (Linux x86_64 binary)
  - `aws-automation` (SAML tool installed via pip)
- **Design:** The container will use a standard `developer` user and expect the host's Kerberos ticket to be mounted.

## Phase 2: Host Integration & Wrapper (`nids-run.sh`)
- Create a script that automates the `podman run` command.
- **Kerberos Bridge:** Use `KRB5CCNAME=FILE:/tmp/krb5cc_$UID` on the host to share tickets with the container.
- **Mounts:**
  - `${PWD}:/workspace:Z` (Project root)
  - `~/.aws:/home/developer/.aws:Z`
  - `~/.ssh:/home/developer/.ssh:ro`
  - `~/.ocp-installer-pull-secret:/home/developer/.ocp-installer-pull-secret:ro`
  - `/tmp/krb5cc_$UID:/tmp/krb5cc_1000:ro` (The Kerberos ticket)

## Phase 3: Script Refactoring
- **`setup.sh`:** Change to build the Podman image instead of local `pip install`.
- **`ocp-cluster-one-shot-4.21.sh`:**
  - Remove logic that downloads `ccoctl` (now in the image).
  - Remove nested `podman run` calls for `ccoctl`; call the binary directly.
  - Simplify pathing to use `/workspace`.

## Phase 4: Validation & Documentation
- Update `NIDS_DEV_CLUSTER_HOW_TO.md` with the new "Podman-first" instructions.
- Verify the SAML flow works seamlessly from host to container.
