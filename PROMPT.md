# Boulder on Kubernetes - Agent Handoff

**Checkpoint:** 2025-08-19T17:04:00.000Z

---

## Current Task

Deploy remaining Boulder services (CA, RA, VA, WFE2, Publisher) and configure mTLS for Boulder SA -> ProxySQL -> MariaDB connections.

---

## Session Requirements  

1. **Check TODO.md** for current 🔄 and 🔴 priority tasks
2. **Follow AGENTS.md** standards (linting, commits, autonomous behavior)
3. **Use existing tools**: `make deploy`, `make health-check`, `make test`
4. **Reference TROUBLESHOOTING.md** for any deployment issues

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
