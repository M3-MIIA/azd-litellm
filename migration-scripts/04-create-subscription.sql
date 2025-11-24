--
-- Script: 04-create-subscription.sql
-- Purpose: Create subscription for logical replication on the new database
-- Target: NEW DATABASE (destination)
--
-- Prerequisites:
--   - Publication created on old database (run 03-create-publication.sql)
--   - New database schema initialized (LiteLLM tables exist)
--   - Network connectivity between old and new databases
--
-- IMPORTANT: You must edit the CONNECTION string below with your actual credentials
--
-- Usage:
--   1. Edit the CONNECTION string in SECTION 3
--   2. psql "postgresql://user:pass@new-db-host:5432/litellmdb?sslmode=require" -f 04-create-subscription.sql
--

-- ==========================================
-- SECTION 1: Pre-flight checks
-- ==========================================

-- Verify we're on the NEW database
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Pre-flight checks';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Connected to database: %', current_database();
    RAISE NOTICE 'PostgreSQL version: %', version();
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT: Ensure this is your NEW (destination) database!';
    RAISE NOTICE '';
END $$;

-- Check if LiteLLM tables exist
DO $$
DECLARE
    table_count int;
BEGIN
    SELECT count(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name LIKE 'LiteLLM_%';

    IF table_count = 0 THEN
        RAISE EXCEPTION 'No LiteLLM tables found! You must initialize the schema first by starting LiteLLM once.';
    ELSE
        RAISE NOTICE '✓ Found % LiteLLM tables', table_count;
    END IF;
END $$;

-- ==========================================
-- SECTION 2: Clean up existing subscriptions
-- ==========================================

-- Drop existing subscription if it exists
DO $$
DECLARE
    sub_count int;
BEGIN
    SELECT count(*) INTO sub_count
    FROM pg_subscription
    WHERE subname = 'litellm_migration';

    IF sub_count > 0 THEN
        RAISE NOTICE 'Subscription "litellm_migration" already exists';
        RAISE NOTICE 'Dropping existing subscription...';
        EXECUTE 'DROP SUBSCRIPTION litellm_migration';
        RAISE NOTICE '✓ Dropped existing subscription';
    END IF;
END $$;

-- ==========================================
-- SECTION 3: Create subscription
-- ==========================================

-- IMPORTANT: Edit this connection string with your OLD database credentials
-- Format: postgresql://username:password@host:port/database?sslmode=require
--
-- You can load this from the config file created by 01-verify-old-config.sh
-- Example with environment variables:
--   \set old_conn_str `echo $OLD_DB_CONNECTION_STRING`
--   CREATE SUBSCRIPTION litellm_migration CONNECTION :'old_conn_str' PUBLICATION litellm_migration;

-- WARNING: Replace the connection string below with your actual OLD database credentials
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Creating subscription';
    RAISE NOTICE '===========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'MANUAL STEP REQUIRED:';
    RAISE NOTICE 'You must create the subscription manually with your connection string.';
    RAISE NOTICE '';
    RAISE NOTICE 'Template command:';
    RAISE NOTICE '';
    RAISE NOTICE 'CREATE SUBSCRIPTION litellm_migration';
    RAISE NOTICE '  CONNECTION ''postgresql://username:password@old-db-host:port/litellmdb?sslmode=require''';
    RAISE NOTICE '  PUBLICATION litellm_migration';
    RAISE NOTICE '  WITH (';
    RAISE NOTICE '    copy_data = true,              -- Copy existing data';
    RAISE NOTICE '    create_slot = true,            -- Create replication slot automatically';
    RAISE NOTICE '    enabled = true,                -- Start replication immediately';
    RAISE NOTICE '    connect = true,                -- Connect to publisher';
    RAISE NOTICE '    streaming = true,              -- Enable streaming for large transactions';
    RAISE NOTICE '    synchronous_commit = ''off''   -- Better performance, acceptable for migration';
    RAISE NOTICE '  );';
    RAISE NOTICE '';
    RAISE NOTICE 'Replace username, password, old-db-host, and port with your actual values.';
    RAISE NOTICE '';
    RAISE NOTICE 'For special characters in password, use URL encoding:';
    RAISE NOTICE '  @ becomes %40';
    RAISE NOTICE '  # becomes %23';
    RAISE NOTICE '  $ becomes %24';
    RAISE NOTICE '  etc.';
    RAISE NOTICE '';
END $$;

-- Uncomment and edit the line below with your actual connection details:
/*
CREATE SUBSCRIPTION litellm_migration
  CONNECTION 'postgresql://your_username:your_password@old-db-host.example.com:5432/litellmdb?sslmode=require'
  PUBLICATION litellm_migration
  WITH (
    copy_data = true,
    create_slot = true,
    enabled = true,
    connect = true,
    streaming = true,
    synchronous_commit = 'off'
  );
*/

-- Alternative: Load connection string from file
-- \set old_db_conn `cat ../migration-scripts/old-instance-config.env | grep OLD_DB_CONNECTION_STRING | cut -d'=' -f2`
-- CREATE SUBSCRIPTION litellm_migration CONNECTION :'old_db_conn' PUBLICATION litellm_migration;

-- ==========================================
-- SECTION 4: Verify subscription creation
-- ==========================================

-- Wait a moment for subscription to initialize
SELECT pg_sleep(2);

-- Check subscription status
DO $$
DECLARE
    sub_count int;
BEGIN
    SELECT count(*) INTO sub_count
    FROM pg_subscription
    WHERE subname = 'litellm_migration';

    IF sub_count = 0 THEN
        RAISE NOTICE '';
        RAISE NOTICE '⚠ Subscription not found!';
        RAISE NOTICE 'You need to manually create the subscription using the template above.';
        RAISE NOTICE '';
    ELSE
        RAISE NOTICE '';
        RAISE NOTICE '===========================================';
        RAISE NOTICE '✓ Subscription created successfully!';
        RAISE NOTICE '===========================================';
        RAISE NOTICE '';
    END IF;
END $$;

-- Display subscription details
SELECT
    subname as subscription_name,
    subenabled as enabled,
    subconninfo as connection_info,
    subpublications as publications
FROM pg_subscription
WHERE subname = 'litellm_migration';

-- Display replication worker status
SELECT
    pid,
    application_name,
    client_addr,
    state,
    sync_state,
    reply_time
FROM pg_stat_replication
WHERE application_name = 'litellm_migration';

-- ==========================================
-- SECTION 5: Monitor initial sync
-- ==========================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Initial synchronization started';
    RAISE NOTICE '===========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'What''s happening now:';
    RAISE NOTICE '  1. Subscription worker connects to old database';
    RAISE NOTICE '  2. Creates replication slot on old database';
    RAISE NOTICE '  3. Begins copying ALL existing data (copy_data=true)';
    RAISE NOTICE '  4. Continues streaming changes in real-time';
    RAISE NOTICE '';
    RAISE NOTICE 'This process may take time depending on database size:';
    RAISE NOTICE '  - Small (< 1 GB): 5-15 minutes';
    RAISE NOTICE '  - Medium (1-10 GB): 15-60 minutes';
    RAISE NOTICE '  - Large (> 10 GB): 1-4 hours';
    RAISE NOTICE '';
    RAISE NOTICE 'Monitor progress with:';
    RAISE NOTICE '  psql -f 05-monitor-replication.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'The old LiteLLM instance can continue operating normally.';
    RAISE NOTICE '';
END $$;

-- ==========================================
-- SECTION 6: Check replication slot on source
-- ==========================================

-- This query should be run on the OLD database to verify slot creation
-- You can run it manually:
-- psql "postgresql://user:pass@old-db-host:5432/litellmdb" -c "SELECT * FROM pg_replication_slots;"

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Verification steps';
    RAISE NOTICE '===========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Run this on the OLD database to verify replication slot:';
    RAISE NOTICE '  SELECT slot_name, active, restart_lsn FROM pg_replication_slots;';
    RAISE NOTICE '';
    RAISE NOTICE 'You should see a slot named "litellm_migration" with active=true';
    RAISE NOTICE '';
END $$;

-- ==========================================
-- TROUBLESHOOTING
-- ==========================================

/*
Common issues and solutions:

1. ERROR: could not connect to the publisher
   Causes:
     - Network connectivity issues
     - Firewall blocking connection
     - Incorrect host/port
     - Database not accepting connections
   Solutions:
     - Test connection: psql "postgresql://user:pass@old-host:port/db"
     - Check firewall rules on old database
     - For AWS RDS: Check security group inbound rules
     - Verify old database accepts connections from new database IP

2. ERROR: publication "litellm_migration" does not exist
   Solution: Create publication on old database first
   Fix: Run 03-create-publication.sql on OLD database

3. ERROR: must be superuser or replication role to create a subscription
   Solution: Grant replication privilege to user
   Fix on OLD database: ALTER USER your_user REPLICATION;

4. ERROR: could not create replication slot
   Causes:
     - max_replication_slots limit reached
     - Slot name already exists
   Solutions:
     - Check existing slots: SELECT * FROM pg_replication_slots;
     - Drop unused slots: SELECT pg_drop_replication_slot('slot_name');
     - Increase max_replication_slots in postgresql.conf

5. WARNING: tables were not subscribed, you will have to run ALTER SUBSCRIPTION ... REFRESH PUBLICATION
   Solution: Table schemas don't match between old and new database
   Fix: Ensure both databases have identical table structures

6. Replication slow or stuck
   Causes:
     - Network latency
     - Old database under heavy load
     - Large tables being copied
   Solutions:
     - Monitor: Run 05-monitor-replication.sql
     - Check network: ping old-db-host
     - Check old DB load: top/htop on old server

To drop the subscription if needed:
   DROP SUBSCRIPTION IF EXISTS litellm_migration;

To disable subscription temporarily:
   ALTER SUBSCRIPTION litellm_migration DISABLE;

To enable subscription:
   ALTER SUBSCRIPTION litellm_migration ENABLE;

To refresh publication (resync table list):
   ALTER SUBSCRIPTION litellm_migration REFRESH PUBLICATION;
*/

-- ==========================================
-- NEXT STEPS
-- ==========================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Next steps';
    RAISE NOTICE '===========================================';
    RAISE NOTICE '';
    RAISE NOTICE '1. Monitor replication progress:';
    RAISE NOTICE '     psql -f 05-monitor-replication.sql';
    RAISE NOTICE '';
    RAISE NOTICE '2. Wait for initial sync to complete (lag near zero)';
    RAISE NOTICE '';
    RAISE NOTICE '3. During sync, old LiteLLM continues operating normally';
    RAISE NOTICE '';
    RAISE NOTICE '4. Once synced, plan your cutover window';
    RAISE NOTICE '';
    RAISE NOTICE '5. During cutover:';
    RAISE NOTICE '     a. Stop old LiteLLM instance';
    RAISE NOTICE '     b. Wait for lag to reach zero';
    RAISE NOTICE '     c. Run 06-sync-sequences.sql';
    RAISE NOTICE '     d. Start new LiteLLM instance';
    RAISE NOTICE '     e. Run 07-validate-migration.sql';
    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
END $$;
