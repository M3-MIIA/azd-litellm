# LiteLLM Database Migration Guide

This guide provides step-by-step instructions for migrating your LiteLLM instance from an old PostgreSQL database to a new one with **minimum downtime** using PostgreSQL logical replication.

## Overview

**Migration Strategy:** PostgreSQL Logical Replication
**Estimated Downtime:** 5-10 minutes (cutover only)
**Suitable For:** Databases 1-100 GB with minimal downtime requirements

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Migration Timeline](#migration-timeline)
3. [Phase 1: Preparation](#phase-1-preparation-no-downtime)
4. [Phase 2: Initial Synchronization](#phase-2-initial-synchronization-no-downtime)
5. [Phase 3: Cutover](#phase-3-cutover-5-10-minutes-downtime)
6. [Phase 4: Validation](#phase-4-validation-post-migration)
7. [Troubleshooting](#troubleshooting)
8. [Rollback Plan](#rollback-plan)

---

## Prerequisites

### Before You Begin

- [ ] Access to both old and new PostgreSQL databases
- [ ] PostgreSQL client tools installed (`psql`, `pg_dump`, `pg_restore`)
- [ ] Network connectivity between old and new databases
- [ ] Sufficient disk space on both databases (recommend 2x current size)
- [ ] Maintenance window scheduled (5-10 minutes)
- [ ] Backup of old database (as safety net)

### Critical Information Required

You **MUST** have these from your old instance:

1. **LITELLM_SALT_KEY** - Critical for encrypted data
2. **LITELLM_MASTER_KEY** - For API authentication
3. **Database credentials** - For both old and new databases
4. **LiteLLM version** - Branch/commit hash from old instance

### PostgreSQL Version Compatibility

- Old and new databases can be different PostgreSQL versions
- Logical replication works across versions (9.4+)
- Recommended: Use same version to avoid compatibility issues

---

## Migration Timeline

| Phase | Duration | Downtime | Description |
|-------|----------|----------|-------------|
| **Phase 1: Preparation** | 1-2 hours | None | Configure databases, verify settings |
| **Phase 2: Initial Sync** | 30 min - 4 hours* | None | Copy all data via replication |
| **Phase 3: Cutover** | 5-10 minutes | **YES** | Stop old, start new instance |
| **Phase 4: Validation** | 1-2 hours | None | Verify migration success |

\* *Duration depends on database size and network speed*

---

## Phase 1: Preparation (No Downtime)

### Step 1.1: Verify and Document Old Configuration

Run the configuration verification script:

```bash
cd migration-scripts
chmod +x 01-verify-old-config.sh
./01-verify-old-config.sh
```

This script will:
- Collect all necessary configuration from old instance
- Test database connectivity
- Document PostgreSQL versions
- Gather table statistics
- Create `old-instance-config.env` file (keep this secure!)

**Important:** Save the generated `old-instance-config.env` file securely. It contains sensitive credentials.

### Step 1.2: Configure New Azure Deployment

Set the **exact same** keys on your new Azure deployment:

```bash
# CRITICAL: Use IDENTICAL values from old instance
azd env set LITELLM_SALT_KEY "<value from old-instance-config.env>"
azd env set LITELLM_MASTER_KEY "<value from old-instance-config.env>"

# Database configuration (already set)
azd env set DATABASE_HOST "<new-db-host>"
azd env set DATABASE_PORT "5432"
azd env set DATABASE_NAME "litellmdb"
azd env set DATABASE_USER "<new-db-user>"
azd env set DATABASE_PASSWORD "<new-db-password>"
```

**Critical:** If `LITELLM_SALT_KEY` doesn't match, encrypted model API keys cannot be decrypted!

### Step 1.3: Deploy New Instance (First Time)

Deploy the new LiteLLM instance to initialize the database schema:

```bash
azd up
```

Wait for deployment to complete, then **stop the new instance**:

```bash
az containerapp update \
  --name <your-container-app-name> \
  --resource-group <your-resource-group> \
  --min-replicas 0 \
  --max-replicas 0
```

Why stop it? We need to populate the database before the application starts serving traffic.

### Step 1.4: Enable Logical Replication on Old Database

Run this script on your **OLD database**:

```bash
# Source the config file
source migration-scripts/old-instance-config.env

# Run the replication setup script
psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" \
  -f migration-scripts/02-enable-logical-replication.sql
```

**For AWS RDS:**
1. Modify your DB parameter group
2. Set `rds.logical_replication = 1`
3. Apply to your RDS instance
4. **Reboot the instance** (required - causes 1-3 min downtime on old instance)

**For self-managed PostgreSQL:**
1. Edit `postgresql.conf`
2. Set:
   ```
   wal_level = logical
   max_replication_slots = 10
   max_wal_senders = 10
   ```
3. Restart PostgreSQL service

After reboot/restart, run the script again to verify settings are applied.

---

## Phase 2: Initial Synchronization (No Downtime)

### Step 2.1: Create Publication on Old Database

Create the publication that will stream changes:

```bash
source migration-scripts/old-instance-config.env

psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" \
  -f migration-scripts/03-create-publication.sql
```

This creates a publication called `litellm_migration` for all tables.

### Step 2.2: Create Subscription on New Database

**Important:** You must manually edit `04-create-subscription.sql` first!

1. Open `migration-scripts/04-create-subscription.sql`
2. Find the commented `CREATE SUBSCRIPTION` command (around line 90)
3. Uncomment and replace with your old database credentials:

```sql
CREATE SUBSCRIPTION litellm_migration
  CONNECTION 'postgresql://your_user:your_password@old-db-host:5432/litellmdb?sslmode=require'
  PUBLICATION litellm_migration
  WITH (
    copy_data = true,
    create_slot = true,
    enabled = true,
    connect = true,
    streaming = true,
    synchronous_commit = 'off'
  );
```

**Special characters in password?** URL-encode them:
- `@` → `%40`
- `#` → `%23`
- `$` → `%24`

Then run the script on your **NEW database**:

```bash
source migration-scripts/old-instance-config.env

psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f migration-scripts/04-create-subscription.sql
```

### Step 2.3: Monitor Replication Progress

The initial data copy will now begin. Monitor progress with:

```bash
source migration-scripts/old-instance-config.env

# One-time check
psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f migration-scripts/05-monitor-replication.sql

# Or continuous monitoring (refresh every 10 seconds)
watch -n 10 "psql \"postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require\" -f migration-scripts/05-monitor-replication.sql"
```

**What to watch for:**
- Table sync status progressing from "Copying data" → "Ready"
- Replication lag decreasing
- Progress percentage increasing

**Duration estimates:**
- Small (< 1 GB): 5-15 minutes
- Medium (1-10 GB): 15-60 minutes
- Large (> 10 GB): 1-4 hours

**During this phase:**
- ✓ Old LiteLLM instance continues running normally
- ✓ Users experience no disruption
- ✓ All changes are automatically replicated to new database

**Wait until:**
- All tables show status "Ready"
- Replication lag is near zero (< 1 MB)
- Progress shows 100% complete

---

## Phase 3: Cutover (5-10 Minutes Downtime)

### Preparation

Before starting cutover:
- [ ] Confirm all tables are synchronized ("Ready" status)
- [ ] Confirm replication lag is near zero
- [ ] Notify users of upcoming maintenance
- [ ] Have rollback plan ready (see below)

### Step 3.1: Stop Old LiteLLM Instance

```bash
# Stop the old Container App or however your old instance is running
# Example for Azure Container Apps:
az containerapp update \
  --name <old-container-app-name> \
  --resource-group <old-resource-group> \
  --min-replicas 0 \
  --max-replicas 0

# Or for other platforms, stop the service/container/pod
```

**Downtime begins here.**

### Step 3.2: Verify Final Replication

Wait 1-2 minutes, then verify replication lag is zero:

```bash
source migration-scripts/old-instance-config.env

psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f migration-scripts/05-monitor-replication.sql
```

Check that "Replication lag" shows "✓ In sync" or very minimal bytes.

### Step 3.3: Synchronize Sequences

Critical step to prevent duplicate key errors:

```bash
source migration-scripts/old-instance-config.env

psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f migration-scripts/06-sync-sequences.sql
```

This resets all auto-increment sequences to match the data.

### Step 3.4: Start New LiteLLM Instance

```bash
# Start the new Container App
az containerapp update \
  --name <new-container-app-name> \
  --resource-group <new-resource-group> \
  --min-replicas 2 \
  --max-replicas 3

# Or use azd
azd deploy litellm
```

Wait for the application to start and become healthy.

### Step 3.5: Verify Application Started

Check the Container App logs:

```bash
az containerapp logs show \
  --name <new-container-app-name> \
  --resource-group <new-resource-group> \
  --follow
```

Look for:
- ✓ No database connection errors
- ✓ No decryption errors (would indicate SALT_KEY mismatch)
- ✓ Application startup successful

**Downtime ends here.**

---

## Phase 4: Validation (Post-Migration)

### Step 4.1: Run Validation Script

```bash
source migration-scripts/old-instance-config.env

psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f migration-scripts/07-validate-migration.sql
```

This will check:
- Table existence and row counts
- Data integrity (NULL checks, relationships)
- Sequence synchronization
- Sample data verification

### Step 4.2: Compare Row Counts

Compare the output with `old-database-stats.txt` (created in Phase 1):

```bash
cat migration-scripts/old-database-stats.txt
```

Key tables to verify:
- `LiteLLM_UserTable` - Should match exactly
- `LiteLLM_TeamTable` - Should match exactly
- `LiteLLM_VerificationToken` - Should match exactly
- `LiteLLM_ProxyModelTable` - Should match exactly
- `LiteLLM_SpendLogs` - May differ slightly if old instance was active during sync

### Step 4.3: Test Application Functionality

Manual testing checklist:

**Basic Access:**
- [ ] Access Swagger UI at `https://your-domain/`
- [ ] Access Admin UI at `https://your-domain/ui`
- [ ] Login works (if using SSO/authentication)

**API Functionality:**
- [ ] Existing API keys work
- [ ] Can make API calls through proxy
- [ ] Responses are correct
- [ ] No errors in logs

**Encrypted Data:**
- [ ] Model configurations load correctly
- [ ] No "Error decrypting value" errors in logs
- [ ] Can make calls to configured models

**Authorization & Budgets:**
- [ ] Team memberships work
- [ ] User permissions enforced correctly
- [ ] Budget limits enforced
- [ ] Rate limiting works

**Data Tracking:**
- [ ] Spend logs update after API calls
- [ ] Usage metrics display correctly
- [ ] Dashboard shows data

### Step 4.4: Monitor for 24-48 Hours

Keep close watch for:
- Application errors in Container App logs
- Database performance issues
- User-reported problems
- Spend tracking accuracy

---

## Troubleshooting

### Issue: "Error decrypting value" in logs

**Cause:** LITELLM_SALT_KEY doesn't match old instance

**Solution:**
1. Get correct SALT_KEY from old instance
2. Update Azure deployment:
   ```bash
   azd env set LITELLM_SALT_KEY "<correct-value>"
   azd deploy litellm
   ```

### Issue: Replication not starting

**Symptoms:**
- No workers in `pg_stat_replication`
- Subscription exists but not active

**Possible causes:**
1. **Network connectivity** - Check firewall rules, security groups
2. **Authentication failure** - Verify connection string credentials
3. **Publication doesn't exist** - Run 03-create-publication.sql

**Debug commands:**
```bash
# On NEW database, check subscription status
psql "..." -c "SELECT * FROM pg_subscription WHERE subname = 'litellm_migration';"

# On OLD database, check for active connections
psql "..." -c "SELECT * FROM pg_stat_replication;"

# Test connectivity
psql "postgresql://user:pass@old-host:5432/litellmdb?sslmode=require" -c "SELECT 1;"
```

### Issue: High replication lag

**Symptoms:**
- Lag not decreasing
- Tables stuck in "Copying data" status

**Possible causes:**
1. **Network bandwidth** - Slow connection between databases
2. **Old database under load** - High CPU/disk usage
3. **Large tables** - Normal for multi-GB tables

**Solutions:**
- Monitor old database performance
- Check network throughput
- Be patient - large tables take time
- Consider using pg_dump/pg_restore instead if lag doesn't improve

### Issue: Duplicate key violations after cutover

**Cause:** Sequences not synchronized properly

**Solution:**
Run 06-sync-sequences.sql again:
```bash
psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f migration-scripts/06-sync-sequences.sql
```

### Issue: Missing data in specific tables

**Cause:**
- Replication not fully caught up
- Table not included in publication

**Check:**
```sql
-- On NEW database
SELECT * FROM pg_subscription_rel WHERE srsubstate != 'r';

-- On OLD database
SELECT * FROM pg_publication_tables WHERE pubname = 'litellm_migration';
```

**Solution:**
If table missing from publication:
```sql
-- On OLD database
ALTER PUBLICATION litellm_migration ADD TABLE "TableName";

-- On NEW database
ALTER SUBSCRIPTION litellm_migration REFRESH PUBLICATION;
```

---

## Rollback Plan

If you encounter issues after cutover, you can quickly rollback:

### Immediate Rollback (Within 1 hour)

1. **Stop new instance:**
   ```bash
   az containerapp update --name <new-app> --resource-group <rg> --min-replicas 0 --max-replicas 0
   ```

2. **Start old instance:**
   ```bash
   az containerapp update --name <old-app> --resource-group <rg> --min-replicas 2 --max-replicas 3
   ```

3. **Update DNS** (if you switched):
   Point back to old instance endpoint

**Downtime:** 2-5 minutes

**Data loss:** None (old database was never touched)

### Extended Rollback (After validation fails)

If you discover issues hours or days later:

1. **Old database is still available** - Simply point your deployment back to it
2. **Keep old database running** for 7-30 days as backup
3. **Don't delete old resources** until fully confident in new instance

---

## Post-Migration Cleanup

**After 7-30 days** of successful operation:

### Step 1: Drop Subscription (NEW Database)

```sql
DROP SUBSCRIPTION IF EXISTS litellm_migration;
```

### Step 2: Drop Publication (OLD Database)

```sql
DROP PUBLICATION IF EXISTS litellm_migration;
```

### Step 3: Drop Replication Slot (OLD Database)

```sql
SELECT pg_drop_replication_slot('litellm_migration');
```

### Step 4: Decommission Old Resources

Once you're 100% confident:
- Shut down old LiteLLM instance
- Take final backup of old database
- Delete old database (or keep as archive)
- Remove old infrastructure resources

---

## Best Practices

### Security

- [ ] Store `old-instance-config.env` securely (contains credentials)
- [ ] Delete config file after migration
- [ ] Use SSL/TLS for all database connections
- [ ] Rotate LITELLM_MASTER_KEY after migration (optional)
- [ ] Never change LITELLM_SALT_KEY after initial setup

### Performance

- [ ] Run migration during off-peak hours
- [ ] Monitor database resource usage during sync
- [ ] Use parallel restore for large databases (`-j` flag)
- [ ] Disable connection pooling temporarily during cutover

### Documentation

- [ ] Document your LITELLM_SALT_KEY securely
- [ ] Keep migration logs
- [ ] Note any issues encountered
- [ ] Update runbooks with new connection strings

---

## Support Resources

### Official Documentation

- [LiteLLM Database Schema](https://docs.litellm.ai/docs/proxy/db_info)
- [PostgreSQL Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- [Azure Database for PostgreSQL](https://learn.microsoft.com/azure/postgresql/)

### Getting Help

If you encounter issues:

1. Check application logs in Azure Container Apps
2. Review this troubleshooting guide
3. Consult LiteLLM documentation
4. Check PostgreSQL logs on both databases

---

## Migration Checklist

Use this checklist to track your progress:

### Pre-Migration
- [ ] Backup old database
- [ ] Run 01-verify-old-config.sh
- [ ] Document LITELLM_SALT_KEY and LITELLM_MASTER_KEY
- [ ] Set identical keys on new deployment
- [ ] Test connectivity to both databases
- [ ] Schedule maintenance window

### Preparation Phase
- [ ] Deploy new instance
- [ ] Stop new instance
- [ ] Enable logical replication on old database
- [ ] Verify replication settings

### Synchronization Phase
- [ ] Create publication (03-create-publication.sql)
- [ ] Edit subscription script with credentials
- [ ] Create subscription (04-create-subscription.sql)
- [ ] Monitor replication progress
- [ ] Wait for all tables to reach "Ready" status
- [ ] Confirm lag is near zero

### Cutover Phase
- [ ] Notify users
- [ ] Stop old instance
- [ ] Verify final replication
- [ ] Sync sequences (06-sync-sequences.sql)
- [ ] Start new instance
- [ ] Verify application starts

### Validation Phase
- [ ] Run validation script (07-validate-migration.sql)
- [ ] Compare row counts
- [ ] Test API functionality
- [ ] Verify encrypted data decrypts
- [ ] Test authentication
- [ ] Monitor logs for errors

### Post-Migration
- [ ] Monitor for 24-48 hours
- [ ] Document any issues
- [ ] Keep old database as backup
- [ ] After 7-30 days, run cleanup
- [ ] Update documentation

---

**Good luck with your migration!**

If you followed this guide, you should have a smooth migration with minimal downtime. Remember to keep the old database as a safety net until you're fully confident in the new deployment.
