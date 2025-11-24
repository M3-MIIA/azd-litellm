--
-- Script: 02-enable-logical-replication.sql
-- Purpose: Enable logical replication on the old PostgreSQL database
-- Target: OLD DATABASE (source)
--
-- IMPORTANT: This script requires PostgreSQL server restart to apply changes.
--            For AWS RDS, use parameter groups. For self-managed, edit postgresql.conf.
--
-- Usage:
--   For AWS RDS:
--     1. Create new parameter group or modify existing one
--     2. Set parameters as shown below
--     3. Apply to RDS instance
--     4. Reboot RDS instance
--
--   For self-managed PostgreSQL:
--     1. Apply these settings to postgresql.conf
--     2. Restart PostgreSQL service
--

-- ==========================================
-- SECTION 1: Check current settings
-- ==========================================

-- Check current replication settings
SELECT
    name,
    setting,
    unit,
    context,
    CASE
        WHEN name = 'wal_level' AND setting != 'logical' THEN 'NEEDS CHANGE'
        WHEN name = 'max_replication_slots' AND setting::int < 10 THEN 'NEEDS CHANGE'
        WHEN name = 'max_wal_senders' AND setting::int < 10 THEN 'NEEDS CHANGE'
        ELSE 'OK'
    END as status
FROM pg_settings
WHERE name IN ('wal_level', 'max_replication_slots', 'max_wal_senders', 'max_worker_processes');

-- ==========================================
-- SECTION 2: Required parameter changes
-- ==========================================

/*
REQUIRED SETTINGS:

1. wal_level = logical
   - Enables logical replication
   - Default: replica
   - Requires: PostgreSQL restart

2. max_replication_slots = 10
   - Number of replication slots allowed
   - Default: 10 (usually sufficient)
   - Requires: PostgreSQL restart

3. max_wal_senders = 10
   - Number of concurrent WAL sender processes
   - Default: 10 (usually sufficient)
   - Requires: PostgreSQL restart

4. max_worker_processes = 10 (optional, recommended)
   - Allows parallel workers for replication
   - Default: 8
   - Requires: PostgreSQL restart

AWS RDS Parameter Group Settings:
- rds.logical_replication = 1
- max_replication_slots = 10
- max_wal_senders = 10

Setting these in RDS automatically configures wal_level=logical.
*/

-- ==========================================
-- SECTION 3: Verify replication readiness
-- ==========================================

-- Check if database is ready for logical replication
DO $$
DECLARE
    wal_level_value text;
    max_slots_value int;
    max_senders_value int;
BEGIN
    -- Get current settings
    SELECT setting INTO wal_level_value FROM pg_settings WHERE name = 'wal_level';
    SELECT setting::int INTO max_slots_value FROM pg_settings WHERE name = 'max_replication_slots';
    SELECT setting::int INTO max_senders_value FROM pg_settings WHERE name = 'max_wal_senders';

    -- Display current status
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Logical Replication Readiness Check';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'wal_level: % (required: logical)', wal_level_value;
    RAISE NOTICE 'max_replication_slots: % (required: >= 10)', max_slots_value;
    RAISE NOTICE 'max_wal_senders: % (required: >= 10)', max_senders_value;
    RAISE NOTICE '';

    -- Check if ready
    IF wal_level_value = 'logical' AND max_slots_value >= 10 AND max_senders_value >= 10 THEN
        RAISE NOTICE 'STATUS: ✓ Database is ready for logical replication!';
        RAISE NOTICE '';
        RAISE NOTICE 'Next step: Run 03-create-publication.sql';
    ELSE
        RAISE NOTICE 'STATUS: ✗ Database is NOT ready for logical replication';
        RAISE NOTICE '';
        RAISE NOTICE 'ACTION REQUIRED:';

        IF wal_level_value != 'logical' THEN
            RAISE NOTICE '  1. Set wal_level = logical';
        END IF;

        IF max_slots_value < 10 THEN
            RAISE NOTICE '  2. Set max_replication_slots = 10 (or higher)';
        END IF;

        IF max_senders_value < 10 THEN
            RAISE NOTICE '  3. Set max_wal_senders = 10 (or higher)';
        END IF;

        RAISE NOTICE '';
        RAISE NOTICE 'For AWS RDS:';
        RAISE NOTICE '  - Modify your DB parameter group';
        RAISE NOTICE '  - Set rds.logical_replication = 1';
        RAISE NOTICE '  - Reboot the RDS instance';
        RAISE NOTICE '';
        RAISE NOTICE 'For self-managed PostgreSQL:';
        RAISE NOTICE '  - Edit postgresql.conf with required settings';
        RAISE NOTICE '  - Restart PostgreSQL service';
        RAISE NOTICE '';
        RAISE NOTICE 'After making changes, run this script again to verify.';
    END IF;
    RAISE NOTICE '===========================================';
END $$;

-- ==========================================
-- SECTION 4: Check existing replication slots
-- ==========================================

-- List any existing replication slots
SELECT
    slot_name,
    plugin,
    slot_type,
    database,
    active,
    restart_lsn,
    confirmed_flush_lsn
FROM pg_replication_slots;

-- Note: If there are existing slots, you may need to drop them if they're unused
-- DROP PUBLICATION IF EXISTS old_slot_name CASCADE;

-- ==========================================
-- SECTION 5: Disk space check
-- ==========================================

-- Check available disk space (important for WAL retention)
SELECT
    pg_size_pretty(pg_database_size(current_database())) as current_db_size,
    pg_size_pretty(sum(pg_total_relation_size(schemaname||'.'||tablename))::bigint) as tables_size
FROM pg_tables
WHERE schemaname = 'public';

-- Note: During replication setup, WAL files will accumulate.
-- Ensure you have at least 2x your database size in free disk space.

-- ==========================================
-- INSTRUCTIONS FOR AWS RDS
-- ==========================================

/*
To enable logical replication on AWS RDS PostgreSQL:

1. Go to RDS Console > Parameter Groups
2. Create a new parameter group or modify existing one
3. Edit parameters:
   - Set: rds.logical_replication = 1
   - This automatically sets wal_level = logical
4. Apply parameter group to your RDS instance
5. Reboot the RDS instance (required for wal_level change)
6. Wait for instance to become available
7. Run this script again to verify settings

Note: The reboot will cause brief downtime (typically 1-3 minutes).
Plan this during a maintenance window if possible.
*/

-- ==========================================
-- INSTRUCTIONS FOR SELF-MANAGED POSTGRESQL
-- ==========================================

/*
To enable logical replication on self-managed PostgreSQL:

1. Edit postgresql.conf (location varies by OS):
   - Linux: /etc/postgresql/{version}/main/postgresql.conf
   - Or find with: SHOW config_file;

2. Add or modify these lines:
   wal_level = logical
   max_replication_slots = 10
   max_wal_senders = 10
   max_worker_processes = 10

3. Restart PostgreSQL:
   - systemctl restart postgresql (systemd)
   - service postgresql restart (init.d)

4. Verify with:
   psql -c "SHOW wal_level;"
   psql -c "SHOW max_replication_slots;"
   psql -c "SHOW max_wal_senders;"

5. Run this script again to verify settings
*/
