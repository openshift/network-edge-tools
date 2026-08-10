# konflux-release

Konflux release workflow automation for the ExternalDNS Operator (EDO).

## Overview

This plugin codifies the 6-phase Konflux release process that the NID team follows for EDO releases, based on the [release process documentation](https://github.com/openshift/external-dns-operator/pull/391) by Andrey Lebedev. Claude drives the workflow end-to-end — opening PRs, creating Release CRs, polling status, running verification — while a human reviewer stays in the loop to approve PRs and handle auth.

## Commands

| Command | Description |
|---------|-------------|
| `/konflux-release:release <version>` | Run the full 6-phase EDO release workflow |
| `/konflux-release:status` | Check current release state and progress |
| `/konflux-release:verify <version>` | Run production verification across all OCP versions |

## Prerequisites

- `oc` CLI authenticated to the Konflux cluster
- `gh` CLI authenticated to GitHub
- `kubectl` access to `external-dns-operator-tenant` namespace
- `podman` installed (for verification)
- `jira` CLI (optional, for closing tickets)

## Setup: Pre-approve Permissions

The release workflow runs many read and write commands. To avoid clicking "Yes" on every `git`, `gh`, `kubectl`, and `podman` command, add these patterns to your EDO repo's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git fetch *)",
      "Bash(git show *)",
      "Bash(git checkout *)",
      "Bash(git branch *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git status*)",
      "Bash(gh pr *)",
      "Bash(gh auth *)",
      "Bash(kubectl get *)",
      "Bash(kubectl apply *)",
      "Bash(oc whoami*)",
      "Bash(grep *)",
      "Bash(sed *)",
      "Bash(cat *)",
      "Bash(wc *)",
      "Bash(podman run *)",
      "Bash(jira issue *)"
    ]
  }
}
```

This only needs to be done once per repo clone.

## Process Phases

1. **Code Readiness** — Verify all PRs merged, VERSION file correct
2. **RPA Verification** — Confirm ReleasePlanAdmission exists in konflux-release-data
3. **Stage Release** — Update FBC catalogs with stage bundle, create stage Release CRs
4. **Prod Bundle Release** — Create prod Release CR for the bundle
5. **FBC Prod Release** — Swap stage→prod registry in catalogs, create 11 FBC Release CRs
6. **Verify + Close** — Verify bundle in all prod indexes, close Jira tickets

## State Tracking

Release state is persisted to `.work/konflux-release/release-state-{version}.json` so the workflow can be resumed across Claude sessions.

## Component Ownership

| Component | Owners |
|-----------|--------|
| Plugin | @Thealisyed |
| EDO release process | @alebedev87, @grzpiotrowski |
