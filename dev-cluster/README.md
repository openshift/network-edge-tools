# NIDS Dev Cluster Setup & Usage Guide

Create and tear down OpenShift developer clusters in the NIDS AWS account from
macOS or Linux. The scripts use Kerberos/SAML for temporary AWS credentials and
run the AWS CLI, OpenShift tools, and internal authentication helper in a
Podman or Docker container.

## Prerequisites

- Connect to the Red Hat corporate VPN to reach internal GitLab and Kerberos.
- Install Podman or Docker, `kinit`/`klist`, `curl`, and Python 3 on the host.
  On macOS, use `brew install krb5 podman python`; on Fedora/RHEL, use
  `sudo dnf install krb5-workstation podman curl python3`.
- Start your container engine. With Podman on macOS, initialize a VM with
  `podman machine init` if needed, then run `podman machine start`.
- Save your [OpenShift pull secret](https://console.redhat.com/openshift/install/pull-secret)
  at `~/.ocp-installer-pull-secret`.
- Ensure `~/.ssh/id_ed25519.pub` exists; use `ssh-keygen -t ed25519` to create a
  key if needed.
- Obtain the NIDS developer AWS account ID from the team.

## Setup

Clone this repository and change into `dev-cluster` before running the scripts:
the wrapper mounts the **current directory** at `/workspace` in the container.

```bash
git clone git@github.com:openshift/network-edge-tools.git
cd network-edge-tools/dev-cluster
export AWS_ACCOUNT_ID="<account_id>"
./setup.sh
```

`setup.sh` checks prerequisites and builds the default `nids-dev` image from
[nids-dev.Containerfile](nids-dev.Containerfile). The image uses RHEL 9 UBI and
includes the internal Red Hat `aws-automation` SAML tool. The wrapper also builds
an image automatically if the selected version and Containerfile checksum do
not already have a matching local image.

## Configuration

Export these variables in the host shell before launching a script:

| Variable | Default | Purpose |
| --- | --- | --- |
| `AWS_ACCOUNT_ID` | Required | NIDS developer AWS account ID. |
| `KERBEROS_ID` | Host `$USER` | Red Hat Kerberos identity. |
| `OCP_REGION` | `us-west-2` | AWS deployment region. |
| `OCP_BASE_DOMAIN` | `nids-dev.devcluster.openshift.com` | Cluster base DNS domain. |
| `CONTAINER_ENGINE` | `podman` | Container engine; `docker` is also supported. |

The default AWS profile is `nids-dev`, and the SAML role is
`${AWS_ACCOUNT_ID}-admin`. Cluster names use the first eight characters of your
username, the date, and a counter stored in `.ocp_cluster_counter`.

Additional script settings such as `OCP_CLUSTER_NAME`, `OCP_ASSET_DIR`,
`SAML_ROLE_NAME`, and `SSH_PUBKEY_PATH` can be set inside a
[manual container shell](#manual-container-shell). The host wrapper forwards
only the account ID, Kerberos identity, username, region, and base domain.
Use container paths for settings inside that shell: the project is mounted at
`/workspace`, and the SSH keys are at `/home/developer/.ssh`.

### Optional password file

The scripts can read a Kerberos password from `~/.krb-passwd` or a `.krb-passwd`
file in the current directory. This stores the password in plain text; if you
choose this option, restrict the file permissions with `chmod 600`. Otherwise,
`kinit` prompts interactively.

## Create a cluster

Run the one-shot script from the host shell in `dev-cluster`:

```bash
./ocp-cluster-one-shot.sh
```

The default is OpenShift 4.21, pinned to `4.21.10`. The available aliases and
their pinned releases are:

| Argument | Release |
| --- | --- |
| `4.19` | `4.19.12` |
| `4.21` | `4.21.10` |
| `5.0` | `5.0.0-ec.3` developer preview |

You can also select an exact z-stream release:

```bash
./ocp-cluster-one-shot.sh 4.19
./ocp-cluster-one-shot.sh 4.22.17
```

The host wrapper selects matching OpenShift tools, mounts the current directory,
Kerberos cache, AWS configuration, SSH keys, and pull secret, then runs the
script inside the container. The installer uses an x86_64 payload and provisions
AWS IAM/OIDC resources with `ccoctl` in manual credentials mode before creating
the cluster. The scripts configure split DNS for the developer domain; the host
configuration may prompt for `sudo`.

Installer state, logs, and credentials are written under `ocp-install-dir/`.
The kubeconfig is at `ocp-install-dir/auth/kubeconfig`. Keep this directory for
teardown. Creating another cluster in the same directory first attempts to
destroy the existing cluster and then replaces the installer assets.

## Manual container shell

```bash
./nids-run.sh
```

For a particular tool version, select the mirror and binary version explicitly:

```bash
OCP_MIRROR_PATH=ocp/4.22.17 OCP_BIN_VERSION=4.22.17 ./nids-run.sh
```

## Tear down a cluster

From the host shell in the same `dev-cluster` directory:

```bash
./ocp-cluster-teardown.sh
```

This refreshes AWS authentication, runs `openshift-install destroy cluster`
against the saved installer state, and removes the asset directory after a
successful destroy.

## Troubleshooting

- **Internal tool installation:** Check VPN connectivity to
  `gitlab.cee.redhat.com`. Build dependencies are installed inside the image.
- **AWS authentication:** Verify the account ID and Kerberos ticket. An expired
  SAML session is refreshed by the AWS helper when you rerun the script.
- **Clock drift:** After laptop sleep, AWS STS or TLS can fail if the container
  VM clock is inaccurate. The wrapper tries to synchronize Podman VM time;
  restart the Podman machine or Docker Desktop if drift persists.
- **Missing `sudo` or `dnsmasq`:** Exit an older container and launch from the
  host so the wrapper can use the image matching the current Containerfile.
- **Pull secret:** Confirm `~/.ocp-installer-pull-secret` contains valid JSON.
- **Container cannot find a script:** Run from `dev-cluster`, as shown above.

## Files and history

- [setup.sh](setup.sh): prerequisite checks and initial image build.
- [nids-run.sh](nids-run.sh): container image selection, authentication mounts,
  and host integration.
- [redhat-aws.sh](redhat-aws.sh): sourced AWS authentication helper.
- [ocp-cluster-one-shot.sh](ocp-cluster-one-shot.sh): cluster creation.
- [ocp-cluster-teardown.sh](ocp-cluster-teardown.sh): cluster destruction.

The scripts and Containerfile were imported from
[`bentito/selfhelp` at `9f12e1c`](https://github.com/bentito/selfhelp/tree/9f12e1cb75c29e62f3a0f431c1dd57b06d44f6a7).
Only trailing whitespace was cleaned up in the imported runtime files.
This README replaces `NIDS_DEV_CLUSTER_HOW_TO.md`. Earlier
[progress notes](docs/archive/CLUSTER_ONE_SHOT_PROGRESS.md) and the
[containerization revision plan](docs/archive/CONTAINER_REVISION_PLAN.md) are
retained as historical documents.
