## 2025-06-23 Boulder SA-1 distroless deployment fix and ProxySQL service decision

- Boulder SA-1 now runs successfully using the distroless image and direct exec of `/boulder` (no shell, no init container).
- Config and secrets are mounted and found by the binary.
- Current error is: `dial tcp: lookup boulder-proxysql on 10.96.0.10:53: no such host`
- **Decision:** Per user instruction, we will fix the ProxySQL service to be named `boulder-proxysql` (option 1), rather than changing Boulder config/secrets.
- This note is for the next agent: after this, commit all changed files including this NOTES.md.

**Next steps:**
- Update the ProxySQL service manifest to use `boulder-proxysql` as the service name.
- Reapply the service and verify Boulder SA-1 can connect.
- Repeat this direct-exec, no-shell pattern for other Boulder microservices as needed.
