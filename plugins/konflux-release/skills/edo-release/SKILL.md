---
name: EDO Konflux Release Workflow
description: Complete 6-phase Konflux release procedure for ExternalDNS Operator (EDO) with state tracking, error handling, and retry logic
---

# EDO Konflux Release Workflow

This skill defines the complete release procedure for ExternalDNS Operator (EDO) through Konflux. It is based on the [Konflux release process documentation](https://github.com/openshift/external-dns-operator/pull/391) created by Andrey Lebedev, combined with operational lessons learned from the EDO v1.2.2 release (OCPBUGS-78658 / NE-2730).

Claude drives each phase end-to-end — creating branches, editing files, opening PRs, creating Release CRs, polling status, and running verification. The human reviewer stays in the loop at natural checkpoints: approving PRs, handling auth, and making judgment calls on failures.

## When to Use This Skill

- **Referenced by**: `/konflux-release:release` command
- **Trigger**: When performing a Konflux release of EDO (any version)
- **Covers**: Both rhel8 (1.2.x on `release-1.2` branch) and rhel9 (1.3.x+ on `main` branch)

## Prerequisites

Before starting, verify:

0. **Permissions**: The EDO repo must have pre-approved bash patterns in `.claude/settings.local.json` (see plugin README). Without this, every `git`, `gh`, `kubectl` command will prompt for manual approval.

1. **Konflux auth**: Run `oc whoami` — if it fails, ask the human to run:
   ```bash
   oc login --web https://api.kflux-prd-rh03.nnv1.p1.openshiftapps.com:6443
   ```
2. **GitHub auth**: Run `gh auth status` — must be authenticated
3. **EDO repo**: Must be cloned locally with `upstream` remote pointing to `openshift/external-dns-operator`
4. **podman**: Must be installed (for Phase 6 verification)
5. **jira CLI**: Optional but needed for closing tickets in Phase 6

## Constants

Load all constants from `team-docs/constants.md`. Key values that vary per release:

| Variable | How to determine |
|----------|-----------------|
| `VERSION` | The target release version (e.g., `1.2.2`, `1.3.6`) |
| `RHEL_BASE` | `rhel8` if version starts with `1.2`, else `rhel9` |
| `RELEASE_BRANCH` | `release-1.2` for rhel8, `main` for rhel9 |
| `BUNDLE_APP` | `ext-dns-optr-1-2-rhel-8` for rhel8, `ext-dns-optr-1-3-rhel-9` for rhel9 |
| `NE_STORY` | The NE Jira story for this release (ask the human) |
| `OCPBUGS_TICKET` | The OCPBUGS CVE/bug ticket driving this release (ask the human) |
| `BUNDLE_DIGEST` | The bundle image digest — discovered during Stage Release |

## State Management

### State File

Persist release state to `.work/konflux-release/release-state-{VERSION}.json` in the EDO repo working directory. Create the `.work/` directory if it doesn't exist (it should be gitignored).

### State Schema

```json
{
  "version": "1.3.6",
  "rhel_base": "rhel9",
  "release_branch": "main",
  "bundle_app": "ext-dns-optr-1-3-rhel-9",
  "ne_story": "NE-2747",
  "ocpbugs_ticket": "OCPBUGS-86279",
  "started_at": "2026-06-17T10:30:00Z",
  "updated_at": "2026-06-17T14:22:00Z",
  "current_phase": 3,
  "phases": {
    "1_code_readiness": { "status": "completed" },
    "2_rpa_verification": { "status": "completed" },
    "3_stage_release": {
      "status": "in_progress",
      "bundle_stage_digest": "sha256:...",
      "fbc_stage_pr": "",
      "release_crs": {}
    },
    "4_prod_bundle": { "status": "pending" },
    "5_fbc_prod": { "status": "pending" },
    "6_verify_close": { "status": "pending" }
  },
  "key_values": {
    "bundle_prod_digest": "",
    "prod_snapshot": "",
    "pr_numbers": [],
    "failed_release_crs": []
  }
}
```

### Resume Logic

At the start of each session:
1. Check if `.work/konflux-release/release-state-{VERSION}.json` exists.
2. If it does, load it and resume from `current_phase`.
3. If not, initialize a new state file and start from Phase 1.
4. After each phase completion, update the state file.

---

## Phase 1: Code Readiness Check

**Goal**: Verify all code changes are merged and the repo is ready for release.

### What Claude Does

1. **Check VERSION file** on the release branch:
   ```bash
   git fetch upstream
   git show upstream/{RELEASE_BRANCH}:VERSION
   ```
   Confirm it matches `{VERSION}`.

2. **Check container_digest.sh**:
   ```bash
   git show upstream/{RELEASE_BRANCH}:bundle-hack/container_digest.sh
   ```
   Verify all image pullspecs are present (operator, operand, kube-rbac-proxy).

3. **Check for open PRs** on the release branch:
   ```bash
   gh pr list --repo openshift/external-dns-operator --base {RELEASE_BRANCH} --state open --json number,title,author
   ```
   Flag any release-related PRs (version bumps, golang bumps, nudging PRs) that haven't merged yet.

4. **Check recent merges** to confirm release prep PRs landed:
   ```bash
   gh pr list --repo openshift/external-dns-operator --base {RELEASE_BRANCH} --state merged --limit 10 --json number,title,mergedAt
   ```

5. **Present checklist** to the human:
   - [ ] VERSION file shows `{VERSION}`
   - [ ] container_digest.sh has all 3 image pullspecs
   - [ ] No blocking open PRs on `{RELEASE_BRANCH}`
   - [ ] Version bump PR merged
   - [ ] Nudging PRs merged (operator digest, operand digest)

### Human Action

Review the checklist. Confirm all items are green, or explain exceptions (e.g., "Konflux references PR is open but Andrey said it's not needed before release").

### State Update

Mark `1_code_readiness.status = "completed"`. Advance `current_phase = 2`.

---

## Phase 2: RPA Verification

**Goal**: Confirm the ReleasePlanAdmission (RPA) exists in the konflux-release-data GitLab repo for this release version.

### What Claude Does

1. **Explain the RPA** to the human:
   > The RPA (ReleasePlanAdmission) defines how Konflux promotes images from stage to prod. It lives in the `konflux-release-data` GitLab repo. Andrey or Greg typically set this up as part of release prep.

2. **Provide the link**:
   > Check: `https://gitlab.cee.redhat.com/releng/konflux-release-data`
   > Look for the EDO tenant's RPA configuration. The `topic` field should reference this release version, and both stage and prod RPAs should exist.

3. **Ask the human** to confirm the RPA is in place.

### Human Action

Navigate to GitLab, check the RPA exists. Report back (e.g., "Yes, Andrey's MR !19004 merged").

### State Update

Mark `2_rpa_verification.status = "completed"`. Advance `current_phase = 3`.

---

## Phase 3: Stage Release

**Goal**: Update FBC catalogs with the stage bundle digest, create stage Release CRs, and verify they succeed.

### Sub-step 3a: Get Stage Bundle Digest

1. **Ask the human** for the stage bundle digest, or look it up:
   ```bash
   kubectl get snapshots -n external-dns-operator-tenant \
     -l appstudio.openshift.io/application={BUNDLE_APP} \
     --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].spec.artifacts.componentDigests}' 2>/dev/null
   ```
   The digest looks like: `sha256:b1fed7a0188328e58b56c9681e567eb02d2de6860315478a33a1ffa24dee9ccc`

2. Save the digest to state: `phases.3_stage_release.bundle_stage_digest`.

### Sub-step 3b: Update FBC Catalogs with Stage Bundle

**IMPORTANT**: FBC catalogs live on the `main` branch, NOT the release branch.

1. **Create a working branch** from `upstream/main`:
   ```bash
   git fetch upstream
   git checkout -b {NE_STORY}-fbc-stage-v{VERSION} upstream/main
   ```

2. **Determine the new catalog entries** needed. For each of the 11 OCP versions (v4.12–v4.22), update both `catalog-template.yaml` and `catalog.yaml`:

   **In `catalog-template.yaml`**: Add a new entry in the `stable-v1` channel and the appropriate `stable-v1.X` minor channel, plus a new `olm.bundle` entry. The new version must:
   - Have `replaces:` pointing to the previous version in the chain
   - Have `skipRange: <{VERSION}`
   - Use `registry.stage.redhat.io` for the bundle image

   Examine the existing entries in a reference catalog-template.yaml to understand the exact format:
   ```bash
   cat catalog/v4.14/catalog-template.yaml
   ```

3. **Apply edits to `catalog-template.yaml` across all 11 versions**. The edits are identical across versions — only the file paths differ. Once all `catalog-template.yaml` files are updated, regenerate the rendered `catalog.yaml` files:
   ```bash
   make generate-catalog
   ```

4. **Verify the changes**:
   ```bash
   git diff --stat
   ```
   Should show 22 files changed (11 catalog-template.yaml + 11 catalog.yaml).

5. **Commit and push**:
   ```bash
   git add catalog/
   git commit -m "{NE_STORY}: Update FBCs v4.12-v4.22 with v{VERSION} stage bundle"
   git push origin {NE_STORY}-fbc-stage-v{VERSION}
   ```

6. **Create PR**:
   ```bash
   gh pr create --repo openshift/external-dns-operator \
     --base main \
     --title "{NE_STORY}: Update FBCs v4.12-v4.22 with v{VERSION} stage bundle" \
     --body "Update FBC catalogs (v4.12-v4.22) with v{VERSION} stage bundle digest.

   Bundle: registry.stage.redhat.io/edo/external-dns-operator-bundle@{BUNDLE_DIGEST}

   Channels updated: stable-v1, stable-v1.X
   Jira: {OCPBUGS_TICKET}"
   ```

7. **Present the PR** to the human for review.

### Sub-step 3c: Create Stage Release CRs

After the PR is merged and Konflux builds the new images:

1. **Capture the merge commit SHA**:
   ```bash
   MERGE_COMMIT_SHA=$(gh pr view {FBC_STAGE_PR_NUMBER} --repo openshift/external-dns-operator \
     --json mergeCommit --jq '.mergeCommit.oid')
   echo "Merge SHA: ${MERGE_COMMIT_SHA}"
   ```
   Save to state: `phases.3_stage_release.fbc_stage_pr_merge_sha`.

2. **Wait for Konflux pipelines** to complete. Monitor using the merge commit SHA:
   ```bash
   kubectl get pipelineruns -n external-dns-operator-tenant \
     -l pac.test.appstudio.openshift.io/sha=${MERGE_COMMIT_SHA}
   ```

3. **Look up the bundle stage snapshot** using the merge commit SHA:
   ```bash
   kubectl get snapshots -n external-dns-operator-tenant \
     -l appstudio.openshift.io/application={BUNDLE_APP},pac.test.appstudio.openshift.io/sha=${MERGE_COMMIT_SHA} \
     -o name
   ```

3. **Create the bundle stage Release CR**:
   ```yaml
   apiVersion: appstudio.redhat.com/v1alpha1
   kind: Release
   metadata:
     name: edo-bundle-stage-{VERSION}-{TIMESTAMP}
     namespace: external-dns-operator-tenant
   spec:
     releasePlan: <stage-release-plan-name>
     snapshot: <snapshot-name>
   ```

   Ask the human to apply: `kubectl apply -f /tmp/release-cr.yaml`

5. **Create FBC stage Release CRs** for all 11 versions. For each version:
   ```bash
   SNAPSHOT=$(kubectl get snapshots -n external-dns-operator-tenant \
     -l appstudio.openshift.io/application=ext-dns-optr-fbc-v4-{VER},pac.test.appstudio.openshift.io/sha=${MERGE_COMMIT_SHA} \
     -o name)
   ```
   Generate a Release CR for each.

5. **Monitor Release CR status** (see Monitoring section below).

### Human Action

- Review and approve the FBC stage PR
- Apply Release CRs when presented
- Handle auth re-login if sessions expire

### State Update

Save PR number, snapshot names, Release CR names and statuses. Mark `3_stage_release.status = "completed"` when all Release CRs succeed. Advance `current_phase = 4`.

---

## Phase 4: Prod Bundle Release

**Goal**: Create the prod Release CR for the operator bundle and verify it succeeds.

### What Claude Does

1. **Verify container_digest.sh** points to `registry.redhat.io` (not stage):
   ```bash
   git show upstream/{RELEASE_BRANCH}:bundle-hack/container_digest.sh
   ```
   All pullspecs should use `registry.redhat.io`. If any use `registry.stage.redhat.io`, generate the edit to swap them and create a PR. (With the mirror set fix from PR #477, this should already point to prod.)

2. **Capture the release branch HEAD commit SHA**:
   ```bash
   git fetch upstream
   RELEASE_COMMIT_SHA=$(git rev-parse upstream/{RELEASE_BRANCH})
   echo "Release SHA: ${RELEASE_COMMIT_SHA}"
   ```

3. **Look up the prod bundle snapshot** using the release commit SHA:
   ```bash
   kubectl get snapshots -n external-dns-operator-tenant \
     -l appstudio.openshift.io/application={BUNDLE_APP},pac.test.appstudio.openshift.io/sha=${RELEASE_COMMIT_SHA} \
     -o name
   ```

4. **Generate the prod Release CR**:
   ```yaml
   apiVersion: appstudio.redhat.com/v1alpha1
   kind: Release
   metadata:
     name: edo-bundle-prod-{VERSION}-{TIMESTAMP}
     namespace: external-dns-operator-tenant
   spec:
     releasePlan: <prod-release-plan-name>
     snapshot: <snapshot-name>
   ```

4. **Present to the human** for `kubectl apply`.

5. **Monitor** until the Release CR shows `Released: True`.

### Human Action

- Apply the Release CR
- Re-login to Konflux if session expired

### State Update

Save snapshot name and Release CR status. Mark `4_prod_bundle.status = "completed"`. Advance `current_phase = 5`.

---

## Phase 5: FBC Prod Release

**Goal**: Swap stage→prod registry in FBC catalogs, merge, create 11 FBC prod Release CRs, and handle failures with retries.

This is the most complex phase. Take it step by step.

### Sub-step 5a: Registry Swap

1. **Create a working branch** from `upstream/main`:
   ```bash
   git fetch upstream
   git checkout -b {NE_STORY}-fbc-prod-v{VERSION} upstream/main
   ```

2. **Swap stage registry to prod** across all 22 catalog files:
   ```bash
   for ver in 12 13 14 15 16 17 18 19 20 21 22; do
     sed -i 's|registry.stage.redhat.io|registry.redhat.io|g' \
       catalog/v4.${ver}/catalog-template.yaml \
       catalog/v4.${ver}/catalog.yaml
   done
   ```

3. **Verify the swap**:
   ```bash
   # Should return 0 — no stage references remain
   grep -r "registry.stage.redhat.io" catalog/ | wc -l

   # Should return matches — prod references present
   grep -c "registry.redhat.io/edo/external-dns-operator-bundle@{BUNDLE_DIGEST}" catalog/v4.14/catalog-template.yaml
   ```

4. **Verify diff**:
   ```bash
   git diff --stat
   ```
   Should show 22 files changed.

### Sub-step 5b: Create PR

1. **Commit and push**:
   ```bash
   git add catalog/
   git commit -m "{NE_STORY}: Update FBCs v4.12-v4.22 with v{VERSION} prod bundle"
   git push origin {NE_STORY}-fbc-prod-v{VERSION}
   ```

2. **Create PR**:
   ```bash
   gh pr create --repo openshift/external-dns-operator \
     --base main \
     --title "{NE_STORY}: Update FBCs v4.12-v4.22 with v{VERSION} prod bundle" \
     --body "Swap stage → prod registry for v{VERSION} bundle in all FBC catalogs (v4.12-v4.22).

   Bundle: registry.redhat.io/edo/external-dns-operator-bundle@{BUNDLE_DIGEST}

   Jira: {OCPBUGS_TICKET}"
   ```

3. **Present the PR** to the human for review.

### Sub-step 5c: Create FBC Prod Release CRs

After the PR merges and Konflux pipelines build new FBC images:

1. **Capture the FBC prod PR merge commit SHA**:
   ```bash
   MERGE_COMMIT_SHA=$(gh pr view {FBC_PROD_PR_NUMBER} --repo openshift/external-dns-operator \
     --json mergeCommit --jq '.mergeCommit.oid')
   echo "Merge SHA: ${MERGE_COMMIT_SHA}"
   ```
   Save to state: `phases.5_fbc_prod.fbc_prod_pr_merge_sha`.

2. **Wait for all 11 FBC pipelines** to complete. Monitor using the merge commit SHA:
   ```bash
   kubectl get pipelineruns -n external-dns-operator-tenant \
     -l pac.test.appstudio.openshift.io/sha=${MERGE_COMMIT_SHA}
   ```

3. **Look up all 11 FBC snapshots** and generate Release CRs:
   ```bash
   for ver in 12 13 14 15 16 17 18 19 20 21 22; do
     SNAPSHOT=$(kubectl get snapshots -n external-dns-operator-tenant \
       -l appstudio.openshift.io/application=ext-dns-optr-fbc-v4-${ver},pac.test.appstudio.openshift.io/sha=${MERGE_COMMIT_SHA} \
       -o name)
     echo "v4.${ver}: ${SNAPSHOT}"
   done
   ```

4. **Generate all 11 Release CRs** as a single YAML file (separated by `---`).

5. **Present to the human** for `kubectl apply -f`.

### Sub-step 5d: Monitor and Retry

1. **Poll all 11 Release CRs**:
   ```bash
   for ver in 12 13 14 15 16 17 18 19 20 21 22; do
     STATUS=$(kubectl get release -n external-dns-operator-tenant \
       {CR_NAME_FOR_VERSION} \
       -o jsonpath='{.status.conditions[?(@.type=="Released")].status}' 2>/dev/null)
     echo "v4.${ver}: ${STATUS:-Pending}"
   done
   ```

2. **Present a status table**:
   ```
   FBC Prod Release Status
   -----------------------
   v4.12: Running
   v4.13: Running
   v4.14: Succeeded ✓
   v4.15: Succeeded ✓
   ...
   v4.22: Failed ✗
   ```

3. **Handle failures** — check the Release CR conditions for error details:
   ```bash
   kubectl get release -n external-dns-operator-tenant {CR_NAME} \
     -o jsonpath='{.status.conditions[?(@.type=="Released")].message}'
   ```

   **Known failure patterns and recovery**:

   | Pattern in error message | Cause | Recovery |
   |--------------------------|-------|----------|
   | `PipelineRunTimeout` or `timed out` | IIB timeout (common on v4.12/v4.13 — larger older indexes) | Create a new Release CR with a new name. May need multiple retries. |
   | `sign-index-image` or `RADAS` | RADAS signing service outage/degradation | Wait 10-15 minutes, then create a new Release CR. |
   | `create-pyxis-image` | Often caused by upstream RADAS issues | Wait and retry, same as signing failures. |

4. **Generate retry Release CRs** for failed versions. Use a new name (append `-retry-{N}`).

5. **Repeat polling** until all 11 versions show `Succeeded`.

### Human Action

- Review and approve the FBC prod PR
- Apply Release CRs and retry CRs when presented
- Handle auth re-login
- Escalate to Andrey/Greg if retries don't resolve failures (especially v4.12/v4.13 IIB timeouts)

### State Update

Track each FBC version's Release CR name and status. Save failed CRs to `key_values.failed_release_crs`. Mark `5_fbc_prod.status = "completed"` when all 11 succeed. Advance `current_phase = 6`.

---

## Phase 6: Verify and Close

**Goal**: Verify the new bundle appears in all production operator indexes, then close Jira tickets.

### Sub-step 6a: Production Verification

1. **Run verification** and collect results:
   ```bash
   for ver in 12 13 14 15 16 17 18 19 20 21 22; do
     RESULT=$(podman run --pull=always --rm --entrypoint /bin/sh \
       registry.redhat.io/redhat/redhat-operator-index:v4.${ver} \
       -c "ls /configs/external-dns-operator/" 2>/dev/null)
     if [ -n "$RESULT" ]; then
       echo "v4.${ver}: FOUND"
     else
       echo "v4.${ver}: NOT FOUND"
     fi
   done
   ```

   **CRITICAL**: Always use `--pull=always` and `--entrypoint /bin/sh`. Without `--pull=always`, podman uses cached index images that may not contain the new bundle. Without the entrypoint override, the command fails because the image's default `ENTRYPOINT` is `/bin/opm`.

2. **Present results table**:
   ```
   Production Verification
   -----------------------
   v4.12: FOUND ✓
   v4.13: FOUND ✓
   ...
   v4.22: FOUND ✓
   ```

4. If any show NOT FOUND:
   - Confirm `--pull=always` was used
   - Check if the Release CR for that version succeeded
   - Image propagation can take a few minutes — wait and retry

### Sub-step 6b: Close Jira Tickets

1. **Close the OCPBUGS ticket** with verification output:
   ```bash
   jira issue move {OCPBUGS_TICKET} "Closed" --resolution "Done" \
     --comment "EDO v{VERSION} released via Konflux. Bundle verified in all production operator indexes (v4.12-v4.22). All {N} FBC Release CRs succeeded."
   ```

2. **Close the NE story**:
   ```bash
   jira issue move {NE_STORY} "Closed" --resolution "Done" \
     --comment "EDO v{VERSION} Konflux release complete. All phases succeeded."
   ```

   Note: NE stories use "Closed" not "Done" as the terminal status.

### Human Action

- Review verification results
- Confirm Jira ticket closure is appropriate
- Post completion update to the team Slack thread

### State Update

Mark `6_verify_close.status = "completed"`. The release is done.

---

## Monitoring Release CRs

This is a reusable pattern used in Phases 3, 4, and 5.

### Polling Loop

```bash
kubectl get release -n external-dns-operator-tenant {CR_NAME} \
  -o jsonpath='{.status.conditions[?(@.type=="Released")]}'
```

Check the `status` field:
- `True` → Succeeded
- `False` → Check `reason` and `message` for failure details
- Empty/missing → Still running

### Poll Frequency

- First check: 2 minutes after creating the Release CR
- Subsequent checks: every 3-5 minutes
- Bundle Release CRs typically complete in 5-15 minutes
- FBC Release CRs take 10-30 minutes (longer for v4.12/v4.13)

### Timeout Expectations

| Component | Typical duration | Timeout concern |
|-----------|-----------------|-----------------|
| Bundle prod release | 5-15 min | Rare |
| FBC v4.14–v4.22 | 10-20 min | Uncommon |
| FBC v4.12–v4.13 | 15-45 min | Common — older indexes are larger |

---

## Error Handling

### Auth Expiry

Konflux sessions expire frequently. Before any `kubectl`/`oc` command sequence:

```bash
oc whoami 2>/dev/null || echo "AUTH_EXPIRED"
```

If expired, tell the human:
> Konflux session expired. Please re-login:
> ```
> oc login --web https://api.kflux-prd-rh03.nnv1.p1.openshiftapps.com:6443
> ```

After re-auth, re-read any snapshot names or CR statuses since the connection context may have changed.

### Error Reference

| Failure | Detection | Recovery |
|---------|-----------|----------|
| Konflux auth expired | `oc whoami` returns error | Human runs `oc login --web` |
| IIB timeout | Release CR message contains `timeout` or `PipelineRunTimeout` | Create new Release CR for failed version |
| RADAS signing failure | Message contains `sign-index-image` or `RADAS` or `create-pyxis-image` | Wait 10-15 min, create new Release CR |
| Snapshot not found | `kubectl get snapshots` returns empty | Verify the push pipeline ran on Konflux UI; may need to trigger rebuild |
| PR merge conflict | `gh pr create` or push fails | Rebase onto latest `upstream/main` and re-push |
| Podman stale cache | Verification shows NOT FOUND despite Release CR success | Re-run with `--pull=always` (mandatory) |
| FBC on wrong branch | Catalog files missing from checkout | FBC catalogs are on `main`, not `release-X.Y` |
| Prow valid-label failure | PR CI check fails | Use NE story number in PR title, not OCPBUGS |

---

## Checkpoint Summary

After each phase, pause and present a status summary to the human:

```
EDO v{VERSION} Konflux Release — Phase {N} Complete
====================================================
Phase 1: Code Readiness      ✓
Phase 2: RPA Verification    ✓
Phase 3: Stage Release        ✓
Phase 4: Prod Bundle Release  ← CURRENT
Phase 5: FBC Prod Release     Pending
Phase 6: Verify + Close       Pending

Next: Phase 4 — Create prod Release CR for the operator bundle.
Proceed? (y/n)
```

Wait for the human to confirm before advancing to the next phase. This is a guided workflow — never proceed to a new phase without explicit confirmation.
