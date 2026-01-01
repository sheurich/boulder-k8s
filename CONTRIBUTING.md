# Contributing

## Pre-Commit Checklist

Before committing, verify:

1. **Research external dependencies** — Check if upstream components support your feature (e.g., vtcombo TLS flags)
2. **Test new components locally** — Run `./scripts/test.sh` before committing new deployments
3. **Complete multi-file changes atomically** — Don't commit partial features that require follow-up fixes
4. **Squash debug commits** — Rebase to remove `debug:` commits before merging

## Lessons Learned

These patterns caused commit churn in this repo. Avoid them.

### 1. Implementing Without Verifying Upstream Support

**Bad:** 4 commits to add Vitess TLS, then 2 reverts when vtcombo didn't support it.

**Fix:** Before implementing features that depend on external components, verify the component supports it. Read entrypoint scripts, check for env var hooks, test in isolation.

### 2. Committing Untested Components

**Bad:** 4 consecutive fixes to aia-test-srv (configMap, image name, Dockerfile, probes).

**Fix:** Test new components end-to-end locally before committing. One working commit beats four fix commits.

### 3. Debug Commits in History

**Bad:** `debug: add verbose logging` followed by `debug: stream logs` clutters history.

**Fix:** Debug locally. If you must commit debug changes, squash them before merging.

### 4. CI/Local Environment Drift

**Bad:** 4 commits trying to fix db-migrate in CI when it worked locally.

**Fix:** Accept that CI environments differ. Document known CI issues rather than churning commits. Local tests are authoritative for functionality.

### 5. Incomplete Feature Checklists

**Bad:** Missing crl-storer secrets, Redis TLS config, port mismatches discovered post-merge.

**Fix:** For multi-component features, maintain a checklist. Verify each component before marking complete.

## Commit Message Format

```
<type>: <description>

[optional body]
```

**Types:** `feat`, `fix`, `refactor`, `test`, `docs`, `chore`

**Avoid:** `debug:` (squash these), `wip:` (don't commit work-in-progress)

## Testing

```bash
./scripts/test.sh              # Run tests (cluster must exist)
./scripts/test.sh --setup      # Setup + test
./scripts/test.sh --reset      # Teardown + setup + test
OVERLAY=dev-vitess ./scripts/test.sh --reset  # Test Vitess backend
```

All 7 tests must pass before committing feature work.
