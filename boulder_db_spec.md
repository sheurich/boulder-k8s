# Boulder Vitess + MySQL Compatibility Spec

This spec describes what a Vitess-backed MySQL endpoint must provide for Boulder to start and run tests/services. It is environment agnostic (K8s, bare metal, any orchestration).

## Required MySQL endpoint
- Expose a MySQL 8.0–compatible listener (Vitess-backed) at a chosen `host:port`.
- Accept a superuser connection (root-equivalent) without grants blocking DDL/DML.
- Keep host/port consistent everywhere Boulder reads DB settings (`DB_ADDR` and the *_dburl files).

## Databases / keyspaces that must already exist
Unsharded (single shard “0”) databases reachable on the endpoint:
- `boulder_sa_test`
- `boulder_sa_integration`
- `incidents_sa_test`
- `incidents_sa_integration`

In upstream Docker this is done by vtcombo `KEYSPACES=...` on startup. If you do not use vtcombo, create these databases/keyspaces yourself before running Boulder migrations.

## Authentication expectation
- Upstream vtcombo uses `mysql_auth_server_impl=none`, so Boulder connects as users named in DSNs without grants.
- If you enforce auth, provision the same users/passwords as in the DSNs you supply, or adjust DSNs accordingly. Boulder will not create users in Vitess mode (`SKIP_USERS=1`).

## Schema and trigger requirements
- Apply Boulder’s migrations to all four databases using `sql-migrate` with a config equivalent to `sa/db/dbconfig.mysql8.yml` (one env per database).
- The integration test `TestIssuanceCertStorageFailed` expects a trigger `fail_ready` on `certificates` that raises an error for `com.wantserror.*` names. Upstream installs it via `test/vtcomboserver/install_trigger.sh` once the `certificates` table exists; replicate this hook or the test will behave differently.

## Boulder runtime configuration to point at your endpoint
Set environment/config so both sources agree on your Vitess endpoint:
- `USE_VITESS=true`
- `DB_ADDR="<host>:<port>"` (used by Go helpers in `test/vars/vars.go`)
- Ensure the DB URL files Boulder reads (the *_dburl contents) contain DSNs pointing to the same host:port and the four databases above (pattern: `user@tcp(host:port)/database?...`).

## Minimal bring-up sequence (reference)
1) Start Vitess/MySQL exposing your `host:port`; ensure the four databases exist.  
2) Wait until a simple query (`SELECT 1`) succeeds on that endpoint.  
3) Run migrations for each of the four databases via `sql-migrate up` using the MySQL8/Vitess DSN config.  
4) Install the `fail_ready` trigger described above.  
5) Launch Boulder with `USE_VITESS=true` and aligned DB URLs/`DB_ADDR`.
