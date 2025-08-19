# Boulder on Kubernetes - Agent Handoff

**Checkpoint:** 2025-08-19T17:04:00.000Z

---

## Current Task

Deploy remaining Boulder services (CA, RA, VA, WFE2, Publisher) and configure mTLS for Boulder SA -> ProxySQL -> MariaDB connections.

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

- ✅ **Infrastructure + Boulder SA**: Operational and database-connected
- 📋 **Next Phase**: Deploy remaining services using `make deploy`

**System Status Check:**
```bash
kubectl get pods -n boulder
# Boulder SA should be Running and Ready
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
- **Recent Commit**: e612b0ec0c1428c5ff86f41327e9ea5ef8a51815
