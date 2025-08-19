# Boulder on Kubernetes - Agent Handoff

**Checkpoint:** 2025-08-19T20:00:00.000Z

---

## Current Task

Complete final Boulder service configuration - fix RA WebPKI certificate mount and CA init container dependencies to enable full service chain.

---

## Session Requirements - START WORK IMMEDIATELY

**CRITICAL: BEGIN WORK AUTONOMOUSLY - DO NOT WAIT FOR INSTRUCTIONS**

1. **FIRST ACTION**: Check `TODO.md` and start working on current 🔄 and 🔴 priority tasks
2. **MANDATORY**: Follow `AGENTS.md` standards (linting, commits, autonomous behavior)
3. **EXECUTE**: Use existing tools (`make deploy`, `make health-check`, `make test`) to progress tasks
4. **REFERENCE**: `TROUBLESHOOTING.md` for any deployment issues
5. **UPDATE**: Mark tasks in progress and commit at logical checkpoints per `AGENTS.md`

---

## Current System State

- ✅ **Infrastructure**: Kind cluster, MariaDB, Redis, ProxySQL, cert-manager all operational
- ✅ **Boulder SA**: **SERVING state confirmed** - validates entire infrastructure foundation
- ✅ **Architecture**: SCT provider eliminated, CA → RA dependency established
- 🔄 **Boulder RA**: 95% complete, WebPKI certificate mount issue only
- 🔄 **Boulder CA**: Init container dependency configuration needs propagation

**System Status Check:**
```bash
make status
# Boulder SA should show "Ready" - CONFIRMED WORKING
# RA shows CrashLoopBackOff - WebPKI mount issue
# CA shows Init:0/1 - waiting for dependencies correctly
```

---

## Success Criteria  

See `reference/SPECp1.md` for complete Phase 1 success criteria.

**Validation Commands:**
```bash
make health-check && make test
```

---

## Essential References

- **Project Overview**: [`README.md`](README.md) - Project introduction, setup, and usage instructions
- **Boulder Reference**: [`reference/BOULDER.md`](reference/BOULDER.md) - Comprehensive technical reference for the upstream Boulder project
- **Task Status**: [`TODO.md`](TODO.md) - Current priorities and task tracking
- **Project Standards**: [`AGENTS.md`](AGENTS.md) - Agent behavior and compliance requirements  
- **Troubleshooting**: [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) - Comprehensive deployment issue resolution
- **Deployment Tools**: [`Makefile`](Makefile) - Automated deployment and validation targets

---

## Handoff Updates Required

Update TODO.md task status and this PROMPT.md before agent transition per AGENTS.md requirements.

**Repository Status:**
- **Current Branch**: augv2
- **Recent Commits**: 
  - 12768b5: Complete Boulder RA service configuration and eliminate SCT provider
  - 83ca325: Resolve Boulder service configuration errors
  - Major infrastructure and SA service completion achieved
