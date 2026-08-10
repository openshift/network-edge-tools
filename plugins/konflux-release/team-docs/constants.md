# EDO Konflux Release Constants

Reference data for ExternalDNS Operator (EDO) Konflux releases.

## Operator Variants

| Property | rhel8 (1.2.x) | rhel9 (1.3.x+) |
|----------|---------------|-----------------|
| Release branch | `release-1.2` | `main` / `release-1.3` |
| Bundle app name | `ext-dns-optr-1-2-rhel-8` | `ext-dns-optr-1-3-rhel-9` |
| Operator image path | `edo/external-dns-rhel8-operator` | `edo/external-dns-rhel9-operator` |
| Operand image path | `edo/external-dns-rhel8` | `edo/external-dns-rhel9` |
| kube-rbac-proxy max version | v4.15 (rhel8 only) | v4.17+ (rhel9) |

## Konflux Infrastructure

| Property | Value |
|----------|-------|
| Konflux cluster | `api.kflux-prd-rh03.nnv1.p1.openshiftapps.com:6443` |
| Konflux UI | `https://konflux-ui.apps.kflux-prd-rh03.nnv1.p1.openshiftapps.com/ns/external-dns-operator-tenant` |
| Namespace | `external-dns-operator-tenant` |
| Login command | `oc login --web https://api.kflux-prd-rh03.nnv1.p1.openshiftapps.com:6443` |

## FBC Catalogs

| Property | Value |
|----------|-------|
| FBC app name pattern | `ext-dns-optr-fbc-v4-{VER}` (e.g., `ext-dns-optr-fbc-v4-14`) |
| OCP versions | v4.12, v4.13, v4.14, v4.15, v4.16, v4.17, v4.18, v4.19, v4.20, v4.21, v4.22 |
| Version numbers (for loops) | `12 13 14 15 16 17 18 19 20 21 22` |
| Catalog directory pattern | `catalog/v4.{VER}/` |
| Files per version | `catalog-template.yaml`, `catalog.yaml` |
| FBC branch | `main` (NOT release-X.Y) |
| OLM channels | `stable-v1` (default), `stable-v1.X` (per minor) |

## Registries

| Registry | URL | Usage |
|----------|-----|-------|
| Stage | `registry.stage.redhat.io` | Stage release bundles |
| Production | `registry.redhat.io` | Prod release bundles |
| Bundle image path | `edo/external-dns-operator-bundle` | Both stage and prod |

## Repos

| Repo | URL |
|------|-----|
| Operator | `https://github.com/openshift/external-dns-operator` |
| Operand | `https://github.com/openshift/external-dns` |
| Release data (GitLab) | `https://gitlab.cee.redhat.com/releng/konflux-release-data` |
| Release process doc | `https://github.com/openshift/external-dns-operator/pull/391` |

## Key Commands

### Snapshot lookup
```bash
kubectl get snapshots -n external-dns-operator-tenant \
  -l appstudio.openshift.io/application={APP_NAME} \
  --sort-by=.metadata.creationTimestamp -o name | tail -1
```

### Release CR status check
```bash
kubectl get release -n external-dns-operator-tenant {NAME} \
  -o jsonpath='{.status.conditions[?(@.type=="Released")].status}'
```

### Auth check
```bash
oc whoami 2>/dev/null || echo "AUTH_EXPIRED"
```

### Podman verification
```bash
podman run --pull=always --rm \
  registry.redhat.io/redhat/redhat-operator-index:v4.{VER} \
  ls /configs/external-dns-operator/
```

## PR Title Convention

PR titles for EDO releases MUST use NE stories (e.g., `NE-2730`), NOT OCPBUGS bug numbers. OCPBUGS numbers fail the `valid-label` Prow check.

Format: `NE-XXXX: <description>`

Example: `NE-2730: Update FBCs v4.12-v4.22 with v1.2.2 prod bundle`
