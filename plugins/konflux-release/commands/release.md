---
description: Run the full 6-phase EDO Konflux release workflow with Claude driving and a human reviewing
argument-hint: "<version> [--resume]"
---

## Name
konflux-release:release

## Synopsis
```
/konflux-release:release <version> [--resume]
```

## Description

The `konflux-release:release` command runs the complete EDO (ExternalDNS Operator) Konflux release workflow. Claude drives each phase — creating branches, editing FBC catalogs, opening PRs, generating Release CRs, polling status, and running verification. The human stays in the loop to review PRs, apply kubectl commands, and handle Konflux auth.

## Implementation

1. **Parse the version argument**. Must match pattern `X.Y.Z` (e.g., `1.2.2`, `1.3.6`).

2. **Determine RHEL base**:
   - Version starts with `1.2` → `rhel8`, release branch `release-1.2`, bundle app `ext-dns-optr-1-2-rhel-8`
   - Version starts with `1.3` or higher → `rhel9`, release branch `main`, bundle app `ext-dns-optr-1-3-rhel-9`

3. **Check for existing state file** at `.work/konflux-release/release-state-{version}.json`:
   - If `--resume` is passed or the file exists, load state and resume from `current_phase`.
   - If the file exists but `--resume` is NOT passed, ask the human: "A release state file exists for v{version} at phase {N}. Resume? (y/n)"
   - If no file exists, initialize a new state and prompt the human for:
     - **NE story number** (e.g., `NE-2730`) — used in PR titles
     - **OCPBUGS ticket** (e.g., `OCPBUGS-78658`) — the CVE/bug driving this release

4. **Verify prerequisites**:
   - `oc whoami` succeeds (Konflux auth)
   - `gh auth status` succeeds (GitHub auth)
   - Current directory is the EDO repo (check for `bundle-hack/container_digest.sh`)

5. **Load constants** from `plugins/konflux-release/team-docs/constants.md` (resolve the absolute path within the network-edge-tools repo).

6. **Follow the `edo-release` skill** at `plugins/konflux-release/skills/edo-release/SKILL.md`. Execute each phase sequentially, updating the state file after each phase checkpoint.

### Prerequisites

- EDO repo must be cloned locally with `upstream` remote → `openshift/external-dns-operator`
- `oc` CLI authenticated to the Konflux cluster
- `gh` CLI authenticated to GitHub
- `kubectl` access to `external-dns-operator-tenant` namespace
- `podman` installed (for Phase 6 verification)
- `jira` CLI (optional, for closing tickets in Phase 6)

## Arguments

- **version** *(required)*
  The target release version in `X.Y.Z` format.
  Example: `1.3.6`

- **--resume** *(optional)*
  Resume an in-progress release from the saved state file without prompting.

## Examples

1. **Start a new release**:
   ```
   /konflux-release:release 1.3.6
   ```

2. **Resume an in-progress release**:
   ```
   /konflux-release:release 1.3.6 --resume
   ```

## See Also
- `plugins/konflux-release/skills/edo-release/SKILL.md` — Detailed phase procedures
- `plugins/konflux-release/team-docs/constants.md` — EDO-specific constants
- `/konflux-release:status` — Check release progress
- `/konflux-release:verify` — Run production verification
