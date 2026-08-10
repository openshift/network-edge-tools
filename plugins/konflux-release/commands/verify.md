---
description: Run production verification for an EDO release across all OCP operator indexes
argument-hint: "<version>"
---

## Name
konflux-release:verify

## Synopsis
```
/konflux-release:verify <version>
```

## Description

The `konflux-release:verify` command verifies that an EDO release bundle is present in all production Red Hat operator indexes (v4.12 through v4.22). It runs `podman` with `--pull=always` to ensure fresh index images are used.

## Implementation

1. **Verify podman is available**:
   ```bash
   which podman
   ```

2. **Run verification across all 11 OCP versions**:
   ```bash
   for ver in 12 13 14 15 16 17 18 19 20 21 22; do
     RESULT=$(podman run --pull=always --rm --entrypoint /bin/sh \
       registry.redhat.io/redhat/redhat-operator-index:v4.${ver} \
       -c "ls /configs/external-dns-operator/" 2>&1)
     EXIT_CODE=$?
     if [ $EXIT_CODE -eq 0 ] && [ -n "$RESULT" ]; then
       echo "v4.${ver}: FOUND"
     else
       echo "v4.${ver}: NOT FOUND"
     fi
   done
   ```

   **CRITICAL**: Always use `--pull=always` and `--entrypoint /bin/sh`. Without `--pull=always`, podman reuses cached index images that may produce false NOT FOUND results. Without the entrypoint override, the command fails because the image's default `ENTRYPOINT` is `/bin/opm`.

3. **Present results as a table**:
   ```
   EDO v{version} Production Verification
   =======================================
   v4.12: FOUND ✓
   v4.13: FOUND ✓
   v4.14: FOUND ✓
   v4.15: FOUND ✓
   v4.16: FOUND ✓
   v4.17: FOUND ✓
   v4.18: FOUND ✓
   v4.19: FOUND ✓
   v4.20: FOUND ✓
   v4.21: FOUND ✓
   v4.22: FOUND ✓

   Result: 11/11 verified ✓
   ```

4. **If any versions show NOT FOUND**, advise:
   - Confirm the FBC prod Release CR for that version succeeded
   - Image propagation may take a few minutes after Release CR success
   - Re-run with `--pull=always` (this command always does, but warn if running manually)

## Arguments

- **version** *(required)*
  The release version to verify (e.g., `1.2.2`).

## Examples

1. **Verify a completed release**:
   ```
   /konflux-release:verify 1.2.2
   ```

## See Also
- `/konflux-release:status` — Check release state
- `/konflux-release:release` — Run the full release workflow
