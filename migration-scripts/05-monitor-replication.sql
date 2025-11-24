--
-- Script: 05-monitor-replication.sql
-- Purpose: Monitor logical replication progress and health
-- Target: Both NEW (subscriber) and OLD (publisher) databases
--
-- Usage:
--   Run on NEW database: psql "postgresql://user:pass@new-db-host:5432/litellmdb" -f 05-monitor-replication.sql
--   Or for continuous monitoring: watch -n 5 'psql "..." -f 05-monitor-replication.sql'
--

\timing off
\pset border 2

-- ==========================================
-- SECTION 1: Subscription status (NEW DB)
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Subscription Status (NEW Database)'
\echo '==========================================='
\echo ''

-- Overall subscription status
SELECT
    subname as subscription_name,
    CASE
        WHEN subenabled THEN '✓ Enabled'
        ELSE '✗ Disabled'
    END as status,
    subpublications as publications,
    -- Hide password from connection string
    regexp_replace(subconninfo, 'password=[^ ]*', 'password=***', 'g') as connection_info_sanitized
FROM pg_subscription
WHERE subname = 'litellm_migration';

-- ==========================================
-- SECTION 2: Replication worker status
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Replication Workers'
\echo '==========================================='
\echo ''

-- Check if workers are running
SELECT
    pid,
    application_name,
    CASE
        WHEN state = 'streaming' THEN '✓ Streaming'
        WHEN state = 'catchup' THEN '⟳ Catching up'
        ELSE state
    END as state,
    CASE
        WHEN sync_state = 'async' THEN 'Async'
        WHEN sync_state = 'sync' THEN 'Sync'
        ELSE sync_state
    END as sync_mode,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, '0/0')) as data_sent,
    pg_size_pretty(pg_wal_lsn_diff(write_lsn, '0/0')) as data_written,
    pg_size_pretty(pg_wal_lsn_diff(flush_lsn, '0/0')) as data_flushed,
    reply_time as last_reply
FROM pg_stat_replication
WHERE application_name = 'litellm_migration';

-- Check if no workers found
DO $$
DECLARE
    worker_count int;
BEGIN
    SELECT count(*) INTO worker_count
    FROM pg_stat_replication
    WHERE application_name = 'litellm_migration';

    IF worker_count = 0 THEN
        RAISE NOTICE '';
        RAISE NOTICE '⚠ WARNING: No replication workers found!';
        RAISE NOTICE '';
        RAISE NOTICE 'Possible causes:';
        RAISE NOTICE '  - Subscription not created yet (run 04-create-subscription.sql)';
        RAISE NOTICE '  - Subscription disabled (check pg_subscription.subenabled)';
        RAISE NOTICE '  - Network connectivity issues';
        RAISE NOTICE '  - Old database not reachable';
        RAISE NOTICE '';
    END IF;
END $$;

-- ==========================================
-- SECTION 3: Replication lag
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Replication Lag'
\echo '==========================================='
\echo ''

-- Calculate replication lag
SELECT
    application_name,
    client_addr as subscriber_ip,
    state,
    -- Lag in bytes
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn)) as send_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), write_lsn)) as write_lag_bytes,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)) as flush_lag_bytes,
    -- Time lag
    CASE
        WHEN state = 'streaming' AND pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) < 1024 THEN '✓ In sync'
        WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) < 1024*1024 THEN '⟳ Minor lag (< 1 MB)'
        WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) < 100*1024*1024 THEN '⚠ Moderate lag (< 100 MB)'
        ELSE '✗ Significant lag (> 100 MB)'
    END as lag_status,
    NOW() - reply_time as time_since_last_reply
FROM pg_stat_replication
WHERE application_name = 'litellm_migration';

-- ==========================================
-- SECTION 4: Table sync status
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Table Synchronization Status'
\echo '==========================================='
\echo ''

-- Show status of each table being replicated
SELECT
    srsubid as subscription_oid,
    CASE srsubstate
        WHEN 'i' THEN '⟳ Initializing'
        WHEN 'd' THEN '📊 Copying data'
        WHEN 's' THEN '⟳ Syncing'
        WHEN 'r' THEN '✓ Ready'
        WHEN 'f' THEN '✗ Failed'
        ELSE srsubstate
    END as status,
    CASE srsubstate
        WHEN 'r' THEN 'Table is synchronized and receiving live updates'
        WHEN 'd' THEN 'Initial data copy in progress'
        WHEN 's' THEN 'Catching up with changes made during copy'
        WHEN 'i' THEN 'Preparing for initial sync'
        WHEN 'f' THEN 'Synchronization failed - check logs'
        ELSE 'Unknown state'
    END as description,
    pg_size_pretty(pg_relation_size(srrelid)) as table_size
FROM pg_subscription_rel
WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration')
ORDER BY
    CASE srsubstate
        WHEN 'f' THEN 1  -- Failed tables first
        WHEN 'd' THEN 2  -- Data copying
        WHEN 's' THEN 3  -- Syncing
        WHEN 'i' THEN 4  -- Initializing
        WHEN 'r' THEN 5  -- Ready (last)
    END,
    pg_relation_size(srrelid) DESC;

-- Count tables by status
SELECT
    CASE srsubstate
        WHEN 'i' THEN 'Initializing'
        WHEN 'd' THEN 'Copying data'
        WHEN 's' THEN 'Syncing'
        WHEN 'r' THEN 'Ready'
        WHEN 'f' THEN 'Failed'
        ELSE 'Unknown'
    END as status,
    count(*) as table_count
FROM pg_subscription_rel
WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration')
GROUP BY srsubstate
ORDER BY
    CASE srsubstate
        WHEN 'f' THEN 1
        WHEN 'd' THEN 2
        WHEN 's' THEN 3
        WHEN 'i' THEN 4
        WHEN 'r' THEN 5
    END;

-- ==========================================
-- SECTION 5: Data copy progress estimate
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Data Copy Progress (Estimate)'
\echo '==========================================='
\echo ''

-- Estimate progress based on row counts
DO $$
DECLARE
    total_tables int;
    ready_tables int;
    copying_tables int;
    progress_pct numeric;
BEGIN
    SELECT count(*) INTO total_tables
    FROM pg_subscription_rel
    WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration');

    SELECT count(*) INTO ready_tables
    FROM pg_subscription_rel
    WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration')
    AND srsubstate = 'r';

    SELECT count(*) INTO copying_tables
    FROM pg_subscription_rel
    WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration')
    AND srsubstate IN ('d', 's');

    IF total_tables > 0 THEN
        progress_pct := (ready_tables::numeric / total_tables::numeric) * 100;

        RAISE NOTICE 'Total tables: %', total_tables;
        RAISE NOTICE 'Ready (synced): %', ready_tables;
        RAISE NOTICE 'In progress: %', copying_tables;
        RAISE NOTICE 'Progress: %% complete', ROUND(progress_pct, 1);
        RAISE NOTICE '';

        IF ready_tables = total_tables THEN
            RAISE NOTICE '✓ All tables synchronized!';
            RAISE NOTICE '';
            RAISE NOTICE 'Initial data copy complete. Now streaming live changes.';
            RAISE NOTICE 'You can proceed with cutover when ready.';
        ELSIF copying_tables > 0 THEN
            RAISE NOTICE '⟳ Initial data copy in progress...';
            RAISE NOTICE 'Please wait for all tables to reach "Ready" status.';
        END IF;
    ELSE
        RAISE NOTICE 'No subscription relation data found.';
        RAISE NOTICE 'Subscription may still be initializing.';
    END IF;
END $$;

-- ==========================================
-- SECTION 6: Row count comparison
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Key Table Row Counts (NEW Database)'
\echo '==========================================='
\echo ''

-- Show row counts for important tables
SELECT
    schemaname || '.' || tablename as table_name,
    n_live_tup as row_count,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size
FROM pg_stat_user_tables
WHERE tablename LIKE 'LiteLLM_%'
ORDER BY n_live_tup DESC
LIMIT 15;

-- ==========================================
-- SECTION 7: Replication slot info (Run on OLD DB)
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Replication Slot Status'
\echo '==========================================='
\echo '(Run the query below on OLD database)'
\echo ''

\echo 'SELECT'
\echo '    slot_name,'
\echo '    plugin,'
\echo '    slot_type,'
\echo '    active,'
\echo '    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag,'
\echo '    restart_lsn,'
\echo '    confirmed_flush_lsn'
\echo 'FROM pg_replication_slots'
\echo 'WHERE slot_name = ''litellm_migration'';'

-- ==========================================
-- SECTION 8: Health summary
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Health Summary'
\echo '==========================================='
\echo ''

DO $$
DECLARE
    sub_enabled boolean;
    worker_count int;
    ready_tables int;
    total_tables int;
    lag_bytes bigint;
    health_status text;
BEGIN
    -- Check subscription enabled
    SELECT subenabled INTO sub_enabled
    FROM pg_subscription
    WHERE subname = 'litellm_migration';

    -- Check worker count
    SELECT count(*) INTO worker_count
    FROM pg_stat_replication
    WHERE application_name = 'litellm_migration';

    -- Check table status
    SELECT count(*) INTO total_tables
    FROM pg_subscription_rel
    WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration');

    SELECT count(*) INTO ready_tables
    FROM pg_subscription_rel
    WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = 'litellm_migration')
    AND srsubstate = 'r';

    -- Check lag
    SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) INTO lag_bytes
    FROM pg_stat_replication
    WHERE application_name = 'litellm_migration'
    LIMIT 1;

    -- Determine overall health
    IF sub_enabled AND worker_count > 0 AND ready_tables = total_tables AND COALESCE(lag_bytes, 0) < 1024*1024 THEN
        health_status := '✓ HEALTHY - Ready for cutover';
    ELSIF sub_enabled AND worker_count > 0 AND ready_tables < total_tables THEN
        health_status := '⟳ IN PROGRESS - Initial sync ongoing';
    ELSIF NOT sub_enabled THEN
        health_status := '✗ DISABLED - Subscription is disabled';
    ELSIF worker_count = 0 THEN
        health_status := '✗ NO WORKERS - Replication not active';
    ELSIF COALESCE(lag_bytes, 0) > 100*1024*1024 THEN
        health_status := '⚠ LAGGING - Significant replication lag';
    ELSE
        health_status := '⚠ CHECK DETAILS - Review status above';
    END IF;

    RAISE NOTICE 'Overall Status: %', health_status;
    RAISE NOTICE '';
    RAISE NOTICE 'Subscription: %', CASE WHEN sub_enabled THEN '✓ Enabled' ELSE '✗ Disabled' END;
    RAISE NOTICE 'Workers: %', CASE WHEN worker_count > 0 THEN format('✓ %s active', worker_count) ELSE '✗ None' END;
    RAISE NOTICE 'Tables synced: % / %', COALESCE(ready_tables, 0), COALESCE(total_tables, 0);

    IF lag_bytes IS NOT NULL THEN
        RAISE NOTICE 'Replication lag: %', pg_size_pretty(lag_bytes);
    END IF;

    RAISE NOTICE '';

    -- Recommendations
    IF ready_tables = total_tables AND COALESCE(lag_bytes, 0) < 1024*1024 THEN
        RAISE NOTICE 'READY FOR CUTOVER!';
        RAISE NOTICE '';
        RAISE NOTICE 'Next steps:';
        RAISE NOTICE '  1. Plan your maintenance window';
        RAISE NOTICE '  2. Stop old LiteLLM instance';
        RAISE NOTICE '  3. Verify lag reaches zero';
        RAISE NOTICE '  4. Run 06-sync-sequences.sql';
        RAISE NOTICE '  5. Start new LiteLLM instance';
    ELSIF ready_tables < total_tables THEN
        RAISE NOTICE 'Wait for initial sync to complete.';
        RAISE NOTICE 'Run this script periodically to monitor progress.';
        RAISE NOTICE '';
        RAISE NOTICE 'Command for continuous monitoring:';
        RAISE NOTICE '  watch -n 10 "psql ... -f 05-monitor-replication.sql"';
    END IF;
END $$;

\echo ''
\echo '==========================================='
\echo 'Monitoring complete'
\echo '==========================================='
\echo ''
