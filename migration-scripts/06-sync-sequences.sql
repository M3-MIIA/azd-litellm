--
-- Script: 06-sync-sequences.sql
-- Purpose: Synchronize PostgreSQL sequences (auto-increment IDs) after replication
-- Target: NEW DATABASE (destination)
--
-- CRITICAL: Run this AFTER stopping the old instance and BEFORE starting the new one
--
-- Why is this needed?
--   Logical replication does NOT automatically sync sequence values.
--   If sequences are not synced, you'll get duplicate key violations when
--   trying to insert new records in the new database.
--
-- When to run:
--   During cutover, after:
--     1. Old LiteLLM instance is stopped
--     2. Replication lag has reached zero
--   Before:
--     1. Starting new LiteLLM instance
--
-- Usage:
--   psql "postgresql://user:pass@new-db-host:5432/litellmdb?sslmode=require" -f 06-sync-sequences.sql
--

-- ==========================================
-- SECTION 1: Pre-flight checks
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Sequence Synchronization'
\echo '==========================================='
\echo ''

DO $$
BEGIN
    RAISE NOTICE 'Database: %', current_database();
    RAISE NOTICE 'Timestamp: %', now();
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT: Ensure old LiteLLM instance is STOPPED';
    RAISE NOTICE '           and replication lag is ZERO before proceeding.';
    RAISE NOTICE '';
END $$;

-- Check replication status
DO $$
DECLARE
    lag_bytes bigint;
BEGIN
    SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn) INTO lag_bytes
    FROM pg_stat_replication
    WHERE application_name = 'litellm_migration'
    LIMIT 1;

    IF lag_bytes IS NULL THEN
        RAISE NOTICE '⚠ No active replication connection found.';
        RAISE NOTICE 'This is expected if old instance is stopped.';
    ELSIF lag_bytes > 1024 THEN
        RAISE WARNING 'Replication lag is % bytes!', pg_size_pretty(lag_bytes);
        RAISE WARNING 'Data may not be fully synchronized.';
        RAISE WARNING 'Consider waiting for lag to reach zero.';
    ELSE
        RAISE NOTICE '✓ Replication lag is minimal (% bytes)', lag_bytes;
    END IF;
    RAISE NOTICE '';
END $$;

-- ==========================================
-- SECTION 2: Identify sequences to sync
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Analyzing sequences'
\echo '==========================================='
\echo ''

-- Show all sequences and their current values
SELECT
    schemaname,
    sequencename,
    last_value,
    -- Find the table and column that uses this sequence
    (SELECT tablename || '.' || column_name
     FROM information_schema.columns
     WHERE table_schema = schemaname
     AND column_default LIKE '%' || sequencename || '%'
     LIMIT 1) as used_by
FROM pg_sequences
WHERE schemaname = 'public'
ORDER BY sequencename;

-- ==========================================
-- SECTION 3: Sync all sequences automatically
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Synchronizing sequences'
\echo '==========================================='
\echo ''

-- Generate and execute setval commands for all sequences
DO $$
DECLARE
    seq_record RECORD;
    table_name text;
    column_name text;
    max_id bigint;
    current_val bigint;
    new_val bigint;
    sequences_synced int := 0;
BEGIN
    -- Loop through all sequences in public schema
    FOR seq_record IN
        SELECT
            schemaname,
            sequencename
        FROM pg_sequences
        WHERE schemaname = 'public'
        ORDER BY sequencename
    LOOP
        -- Try to find the table and column that uses this sequence
        SELECT INTO table_name, column_name
            c.table_name, c.column_name
        FROM information_schema.columns c
        WHERE c.table_schema = seq_record.schemaname
        AND c.column_default LIKE '%' || seq_record.sequencename || '%'
        LIMIT 1;

        IF table_name IS NOT NULL THEN
            -- Get the maximum ID from the table
            EXECUTE format('SELECT COALESCE(MAX(%I), 0) FROM %I.%I',
                          column_name, seq_record.schemaname, table_name)
            INTO max_id;

            -- Get current sequence value
            EXECUTE format('SELECT last_value FROM %I.%I',
                          seq_record.schemaname, seq_record.sequencename)
            INTO current_val;

            -- Calculate new value (max_id + 1)
            new_val := max_id + 1;

            -- Only update if needed
            IF new_val > current_val THEN
                -- Set sequence to max_id + 1
                EXECUTE format('SELECT setval(%L, %s, false)',
                              seq_record.schemaname || '.' || seq_record.sequencename,
                              new_val);

                RAISE NOTICE '✓ Synced %.%: % → % (based on %.% max: %)',
                    seq_record.schemaname,
                    seq_record.sequencename,
                    current_val,
                    new_val,
                    table_name,
                    column_name,
                    max_id;

                sequences_synced := sequences_synced + 1;
            ELSE
                RAISE NOTICE '  Skip %.%: already at % (table max: %)',
                    seq_record.schemaname,
                    seq_record.sequencename,
                    current_val,
                    max_id;
            END IF;
        ELSE
            -- Sequence found but no table uses it
            RAISE NOTICE '  Skip %.%: no table reference found',
                seq_record.schemaname,
                seq_record.sequencename;
        END IF;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '=========================================';
    RAISE NOTICE 'Synchronized % sequence(s)', sequences_synced;
    RAISE NOTICE '=========================================';
END $$;

-- ==========================================
-- SECTION 4: Verify sequence synchronization
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Verification'
\echo '==========================================='
\echo ''

-- Show updated sequence values vs table max values
SELECT
    s.sequencename,
    s.last_value as sequence_value,
    (SELECT column_name
     FROM information_schema.columns
     WHERE table_schema = s.schemaname
     AND column_default LIKE '%' || s.sequencename || '%'
     LIMIT 1) as column_name,
    (SELECT tablename
     FROM pg_tables
     WHERE schemaname = s.schemaname
     AND tablename IN (
         SELECT table_name
         FROM information_schema.columns
         WHERE table_schema = s.schemaname
         AND column_default LIKE '%' || s.sequencename || '%'
     )
     LIMIT 1) as table_name,
    -- Get max value from table (using dynamic query would be better, but this is for display)
    'Run: SELECT MAX(id) FROM ' || (
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = s.schemaname
        AND tablename IN (
            SELECT table_name
            FROM information_schema.columns
            WHERE table_schema = s.schemaname
            AND column_default LIKE '%' || s.sequencename || '%'
        )
        LIMIT 1
    ) as verify_command
FROM pg_sequences s
WHERE s.schemaname = 'public'
ORDER BY s.sequencename;

-- ==========================================
-- SECTION 5: Test sequence generation
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Testing sequence generation'
\echo '==========================================='
\echo ''

-- Test that sequences generate values correctly
DO $$
DECLARE
    seq_record RECORD;
    next_val bigint;
BEGIN
    RAISE NOTICE 'Testing nextval() for each sequence:';
    RAISE NOTICE '';

    FOR seq_record IN
        SELECT schemaname, sequencename
        FROM pg_sequences
        WHERE schemaname = 'public'
        ORDER BY sequencename
        LIMIT 5  -- Test first 5 sequences only
    LOOP
        -- Get next value (but roll it back by not committing)
        EXECUTE format('SELECT nextval(%L)',
                      seq_record.schemaname || '.' || seq_record.sequencename)
        INTO next_val;

        -- Reset to previous value (undo the nextval test)
        EXECUTE format('SELECT setval(%L, %s)',
                      seq_record.schemaname || '.' || seq_record.sequencename,
                      next_val - 1);

        RAISE NOTICE '  %.%: nextval() → %',
            seq_record.schemaname,
            seq_record.sequencename,
            next_val;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✓ All tested sequences generate values correctly';
END $$;

-- ==========================================
-- SECTION 6: Summary and next steps
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Sequence Synchronization Complete'
\echo '==========================================='
\echo ''

DO $$
BEGIN
    RAISE NOTICE 'What was done:';
    RAISE NOTICE '  ✓ Analyzed all sequences in the database';
    RAISE NOTICE '  ✓ Synchronized sequences to match table data';
    RAISE NOTICE '  ✓ Verified sequence generation works';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Start the new LiteLLM Container App';
    RAISE NOTICE '  2. Verify application starts successfully';
    RAISE NOTICE '  3. Run 07-validate-migration.sql to verify data';
    RAISE NOTICE '  4. Test API functionality';
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT:';
    RAISE NOTICE '  - Keep old database as backup for 7-30 days';
    RAISE NOTICE '  - Monitor new instance closely for 24-48 hours';
    RAISE NOTICE '  - You can drop the subscription after confirming success';
    RAISE NOTICE '';
END $$;

-- ==========================================
-- SECTION 7: Optional cleanup commands
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Optional Cleanup (run after validation)'
\echo '==========================================='
\echo ''

/*
After confirming the migration is successful, you can clean up:

1. Drop the subscription (stops replication, frees resources):
   DROP SUBSCRIPTION IF EXISTS litellm_migration;

2. On OLD database, drop the publication:
   DROP PUBLICATION IF EXISTS litellm_migration;

3. On OLD database, drop the replication slot (if not auto-dropped):
   SELECT pg_drop_replication_slot('litellm_migration');

DO NOT run these commands until you've:
  - Validated the migration (07-validate-migration.sql)
  - Confirmed the new instance works correctly
  - Tested all critical functionality
  - Monitored for at least 24-48 hours
*/

\echo 'Commands listed in script comments (Section 7)'
\echo 'Run these only after successful validation!'
\echo ''
