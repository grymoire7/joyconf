# Fly.io App & Database Migration / Rename

Fly.io has no rename command for apps or Postgres clusters. To rename either,
you create a new one, migrate data, then destroy the old one. This document
records what actually worked when renaming `joyconf` → `speechwave`.

## Overview

1. Create new Fly app
2. Create new Postgres cluster
3. Dump source database and restore into new cluster over the internal network
4. Attach new cluster to new app (creates `DATABASE_URL` secret)
5. Grant the new app role permissions on the restored tables
6. Set remaining secrets and deploy
7. Verify, then destroy old resources

---

## Step-by-step

### 1. Create the new app

```bash
fly apps create <new-app-name>
```

### 2. Create the new Postgres cluster

Match the region and Postgres version of the source cluster. Use
`fly image show -a <source-db>` to confirm the version.

```bash
fly pg create --name <new-db-name> --region <region> \
  --vm-size shared-cpu-1x --volume-size 10 --initial-cluster-size 1
```

Save the printed `postgres` user password — it's only shown once.

### 3. Get source DB credentials

`fly pg` commands are interactive-only; SSH is the reliable path.

**Important:** On Fly Postgres Flex, TCP connections to `localhost` require a
password. The `SU_PASSWORD` environment variable holds the password for the
`flypgadmin` superuser (not `postgres`). Connect on port **5433** (direct
Postgres, bypassing HAProxy on 5432).

```bash
# Get SU_PASSWORD from source cluster
fly ssh console -a <source-db> --command "/bin/sh -c 'echo \$SU_PASSWORD'"
```

Verify it works:
```bash
fly ssh console -a <source-db> --command \
  "/bin/sh -c 'PGPASSWORD=<su_password> psql -U flypgadmin -h localhost -p 5433 -d postgres -c \"\\l\"'"
```

### 4. Create the target database

From inside the source cluster's SSH session, reach the new cluster over
the Fly private network using its `.internal` hostname:

```bash
fly ssh console -a <source-db> --command \
  "/bin/sh -c 'PGPASSWORD=<new-db-postgres-password> createdb -U postgres -h <new-db>.internal <new-db-name> && echo created'"
```

### 5. Dump and restore over the internal network

Run this as a single piped command from the source machine. The source uses
`flypgadmin` on port 5433; the destination uses `postgres` on port 5432
(HAProxy, which is fine for writes):

```bash
fly ssh console -a <source-db> --command "/bin/sh -c \
  'PGPASSWORD=<su_password> pg_dump -U flypgadmin -h localhost -p 5433 -d <source-db-name> \
   | PGPASSWORD=<new-db-postgres-password> psql -U postgres -h <new-db>.internal -p 5432 -d <new-db-name>'"
```

**Expected output:** A stream of `SET`, `CREATE TABLE`, `COPY N`, `ALTER TABLE`
lines. You will see `ERROR: role "<old-app-name>" does not exist` for ownership
transfers — this is harmless. The data copies correctly regardless.

Verify row counts to confirm:
```bash
fly ssh console -a <source-db> --command \
  "/bin/sh -c 'PGPASSWORD=<new-db-postgres-password> psql -U postgres -h <new-db>.internal -p 5432 -d <new-db-name> \
   -c \"SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY relname\"'"
```

### 6. Attach the new cluster to the new app

The `-y` flag is required for non-interactive use:

```bash
fly pg attach <new-db-name> --app <new-app-name> \
  --database-name <new-db-name> --database-user <new-app-name> -y
```

This creates a `<new-app-name>` Postgres role and sets `DATABASE_URL` on the
app. Note the generated password in the output.

### 7. Grant table permissions to the new role

The restored tables are owned by `postgres`, not the newly created app role.
Connect as `postgres` and grant access:

```bash
fly ssh console -a <source-db> --command "/bin/sh -c \
  'PGPASSWORD=<new-db-postgres-password> psql -U postgres -h <new-db>.internal -p 5432 -d <new-db-name> -c \
   \"GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO <new-app-name>;
     GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO <new-app-name>;
     GRANT ALL PRIVILEGES ON SCHEMA public TO <new-app-name>;
     ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO <new-app-name>;
     ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO <new-app-name>;\"'"
```

Verify the app role can actually query:
```bash
fly ssh console -a <source-db> --command \
  "/bin/sh -c 'PGPASSWORD=<app-role-password> psql -U <new-app-name> -h <new-db>.internal -p 5432 -d <new-db-name> -c \"\\dt\"'"
```

### 8. Set secrets and deploy

Stage secrets before deploying so they go out in a single deploy:

```bash
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)" --app <new-app-name> --stage
fly secrets set ADMIN_PASSWORD="..." --app <new-app-name> --stage
fly deploy
```

`DATABASE_URL` was already set by `fly pg attach` in step 6.

### 9. Verify

Hit the app and confirm it works end-to-end.

If you see `tcp recv (idle): closed` DB errors in `fly logs` immediately after
the first deploy, **this is a timing issue** — HAProxy on the new Postgres
cluster needs a moment to resolve its internal DNS on first boot. The machines
will autostop. Start one manually and the errors will be gone:

```bash
fly machine start <machine-id> -a <new-app-name>
```

### 10. Destroy old resources

Only after confirming the new app works:

```bash
fly apps destroy <old-app-name> -y
fly apps destroy <old-db-name> -y
```

---

## Troubleshooting reference

| Symptom | Cause | Fix |
|---|---|---|
| `fly pg import` fails with "non interactive" | The command requires a TTY | Use the SSH + pg_dump pipe approach in step 5 |
| `fly pg attach` fails with "non interactive" | Missing `-y` flag | Add `-y` to the command |
| `FATAL: password authentication failed for user "postgres"` | No Unix socket; TCP requires a password, and `SU_PASSWORD` is for `flypgadmin`, not `postgres` | Use `-U flypgadmin` with `SU_PASSWORD` on port 5433 |
| `ERROR: role "<old-name>" does not exist` during restore | The old app's DB role doesn't exist on the new cluster yet | Harmless — data still copies; grant access after attach (step 7) |
| `tcp recv (idle): closed` on first deploy | HAProxy DNS resolution warming up on new cluster | Wait or manually start a machine; resolves on its own |
| App role can't query tables after attach | Tables are owned by `postgres`, not the app role | Run the `GRANT` commands in step 7 |
