---
description: Check the current state and progress of an in-progress EDO Konflux release
argument-hint: "[version]"
---

## Name
konflux-release:status

## Synopsis
```
/konflux-release:status [version]
```

## Description

The `konflux-release:status` command reads the release state file and reports the current phase, completed phases, and any failed Release CRs. If Konflux auth is active, it also polls live Release CR statuses.

## Implementation

1. **Find state files**. Look for `.work/konflux-release/release-state-*.json` in the current directory:
   - If `version` is provided, read `release-state-{version}.json` directly.
   - If no version is provided, list all state files and report on the most recent one.
   - If no state files exist, report "No active releases found."

2. **Read and parse** the state JSON file.

3. **Display the phase summary**:
   ```
   EDO v{version} Konflux Release Status
   ======================================
   Phase 1: Code Readiness       ✓ Completed
   Phase 2: RPA Verification     ✓ Completed
   Phase 3: Stage Release         ✓ Completed
   Phase 4: Prod Bundle Release   → In Progress
   Phase 5: FBC Prod Release      · Pending
   Phase 6: Verify + Close        · Pending

   Current phase: 4 — Prod Bundle Release
   Started: 2026-06-17 10:30 UTC
   Last updated: 2026-06-17 14:22 UTC
   ```

4. **Show key values** if populated:
   - Bundle digest
   - Snapshot name
   - PR numbers
   - Failed Release CRs (with error messages if available)

5. **Optionally poll live status** if Konflux auth is active (`oc whoami` succeeds):
   - Check Release CR status for the current phase
   - Report live status alongside saved state

## Arguments

- **version** *(optional)*
  The release version to check. If omitted, shows the most recent active release.

## Examples

1. **Check a specific release**:
   ```
   /konflux-release:status 1.3.6
   ```

2. **Check the most recent release**:
   ```
   /konflux-release:status
   ```
