# LiteLLM Database Migration Scripts

This directory contains scripts for migrating LiteLLM data from an old PostgreSQL database to a new one using PostgreSQL logical replication.

## Quick Start

1. **Read the main guide first:** [MIGRATION-GUIDE.md](../MIGRATION-GUIDE.md)
2. **Run scripts in order:**
   - 01-verify-old-config.sh
   - 02-enable-logical-replication.sql
   - 03-create-publication.sql
   - 04-create-subscription.sql
   - 05-monitor-replication.sql (repeatedly, until synced)
   - 06-sync-sequences.sql (during cutover)
   - 07-validate-migration.sql (after cutover)

## Scripts Overview

### 01-verify-old-config.sh
**Purpose:** Collect and verify configuration from old instance
**Target:** Run locally (interactive)
**Output:** `old-instance-config.env` (contains credentials - keep secure!)

**Usage:**
```bash
chmod +x 01-verify-old-config.sh
./01-verify-old-config.sh
```

### 02-enable-logical-replication.sql
**Purpose:** Enable logical replication on old PostgreSQL database
**Target:** OLD database
**Note:** Requires database restart

**Usage:**
```bash
source old-instance-config.env
psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" \
  -f 02-enable-logical-replication.sql
```

### 03-create-publication.sql
**Purpose:** Create publication for replication
**Target:** OLD database

**Usage:**
```bash
source old-instance-config.env
psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" \
  -f 03-create-publication.sql
```

### 04-create-subscription.sql
**Purpose:** Create subscription to receive replicated data
**Target:** NEW database
**⚠️ Important:** Must edit script first to add connection string!

**Usage:**
1. Edit the script and uncomment the `CREATE SUBSCRIPTION` command
2. Replace connection string with your old database credentials
3. Run:
```bash
source old-instance-config.env
psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f 04-create-subscription.sql
```

### 05-monitor-replication.sql
**Purpose:** Monitor replication progress and health
**Target:** NEW database
**Note:** Run repeatedly until sync is complete

**Usage:**
```bash
# One-time check
source old-instance-config.env
psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f 05-monitor-replication.sql

# Continuous monitoring (refresh every 10 seconds)
watch -n 10 "psql \"postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require\" -f 05-monitor-replication.sql"
```

### 06-sync-sequences.sql
**Purpose:** Synchronize auto-increment sequences after replication
**Target:** NEW database
**⚠️ Critical:** Run AFTER stopping old instance, BEFORE starting new one

**Usage:**
```bash
source old-instance-config.env
psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f 06-sync-sequences.sql
```

### 07-validate-migration.sql
**Purpose:** Validate data integrity and completeness
**Target:** NEW database
**Note:** Run after new instance is started

**Usage:**
```bash
source old-instance-config.env
psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" \
  -f 07-validate-migration.sql
```

## Migration Flow Diagram

```
Phase 1: Preparation
┌─────────────────────────────────────────────┐
│ 01-verify-old-config.sh                     │
│   ↓ Creates old-instance-config.env         │
│ Configure new Azure deployment              │
│   ↓ Set LITELLM_SALT_KEY (must match!)      │
│ Deploy new instance, then stop it           │
│   ↓                                          │
│ 02-enable-logical-replication.sql (OLD DB)  │
│   ↓ Requires database restart               │
└─────────────────────────────────────────────┘

Phase 2: Synchronization (No Downtime)
┌─────────────────────────────────────────────┐
│ 03-create-publication.sql (OLD DB)          │
│   ↓ Creates "litellm_migration" publication │
│ 04-create-subscription.sql (NEW DB)         │
│   ↓ Starts data copy                        │
│ 05-monitor-replication.sql (NEW DB)         │
│   ↓ Run repeatedly until lag = 0            │
│ Wait for all tables to reach "Ready"        │
└─────────────────────────────────────────────┘

Phase 3: Cutover (5-10 min Downtime)
┌─────────────────────────────────────────────┐
│ Stop old LiteLLM instance                   │
│   ↓ Downtime begins                         │
│ Verify replication lag is zero              │
│   ↓                                          │
│ 06-sync-sequences.sql (NEW DB)              │
│   ↓ Prevents duplicate key errors           │
│ Start new LiteLLM instance                  │
│   ↓ Downtime ends                           │
└─────────────────────────────────────────────┘

Phase 4: Validation
┌─────────────────────────────────────────────┐
│ 07-validate-migration.sql (NEW DB)          │
│   ↓ Verify data integrity                   │
│ Test application functionality              │
│   ↓ Monitor for 24-48 hours                 │
│ Keep old database as backup                 │
└─────────────────────────────────────────────┘
```

## Important Notes

### CRITICAL: LITELLM_SALT_KEY
- **Must be identical** on old and new instances
- Used to encrypt/decrypt model API keys
- **Cannot be changed** after initial setup
- If lost or mismatched, encrypted data is unrecoverable

### Security
- `old-instance-config.env` contains sensitive credentials
- **Keep it secure** and delete after migration
- Never commit it to version control
- Use SSL/TLS for all database connections

### Timing
- **Preparation Phase:** 1-2 hours
- **Sync Phase:** 30 min - 4 hours (depends on DB size)
- **Cutover:** 5-10 minutes (only downtime)
- **Validation:** 1-2 hours

### Database Size Guidelines
- **Small (< 1 GB):** Very fast, sync in 5-15 minutes
- **Medium (1-10 GB):** This approach is optimal, 15-60 min sync
- **Large (> 10 GB):** Still works, but sync takes 1-4 hours

## Troubleshooting

### Connection Issues
```bash
# Test old database connection
psql "postgresql://user:pass@old-host:5432/litellmdb?sslmode=require" -c "SELECT version();"

# Test new database connection
psql "postgresql://user:pass@new-host:5432/litellmdb?sslmode=require" -c "SELECT version();"
```

### Special Characters in Password
URL-encode special characters:
- `@` → `%40`
- `#` → `%23`
- `$` → `%24`
- `&` → `%26`
- `=` → `%3D`
- `+` → `%2B`

### Check Replication Status
```sql
-- On OLD database: Check if subscription connected
SELECT * FROM pg_stat_replication WHERE application_name = 'litellm_migration';

-- On NEW database: Check subscription status
SELECT * FROM pg_subscription WHERE subname = 'litellm_migration';

-- On NEW database: Check table sync progress
SELECT srsubstate, count(*) FROM pg_subscription_rel
WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration')
GROUP BY srsubstate;
```

### View Logs
```bash
# Azure Container Apps logs
az containerapp logs show \
  --name <your-app-name> \
  --resource-group <your-rg> \
  --follow

# Or use Azure Portal → Container App → Log stream
```

## Generated Files

After running the scripts, you'll have:

- `old-instance-config.env` - Configuration and credentials (DELETE after migration!)
- `old-database-stats.txt` - Table statistics from old database
- Various PostgreSQL log outputs

## Cleanup After Migration

After 7-30 days of successful operation:

```sql
-- On NEW database
DROP SUBSCRIPTION IF EXISTS litellm_migration;

-- On OLD database
DROP PUBLICATION IF EXISTS litellm_migration;
SELECT pg_drop_replication_slot('litellm_migration');
```

## Support

For detailed information, see [MIGRATION-GUIDE.md](../MIGRATION-GUIDE.md)

For LiteLLM-specific questions, consult:
- [LiteLLM Database Documentation](https://docs.litellm.ai/docs/proxy/db_info)
- [LiteLLM Security & Encryption FAQ](https://docs.litellm.ai/docs/proxy/security_encryption_faq)
