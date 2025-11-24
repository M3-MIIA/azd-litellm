--
-- Script: 03-create-publication.sql
-- Purpose: Create publication for logical replication on the old database
-- Target: OLD DATABASE (source)
--
-- Prerequisites:
--   - Logical replication must be enabled (wal_level = logical)
--   - Run 02-enable-logical-replication.sql first
--
-- Usage:
--   psql "postgresql://user:pass@old-db-host:5432/litellmdb?sslmode=require" -f 03-create-publication.sql
--

-- ==========================================
-- SECTION 1: Pre-flight checks
-- ==========================================

-- Verify logical replication is enabled
DO $$
DECLARE
    wal_level_value text;
BEGIN
    SELECT setting INTO wal_level_value FROM pg_settings WHERE name = 'wal_level';

    IF wal_level_value != 'logical' THEN
        RAISE EXCEPTION 'Logical replication is not enabled. wal_level is % but must be "logical". Run 02-enable-logical-replication.sql first.', wal_level_value;
    ELSE
        RAISE NOTICE '✓ Logical replication is enabled (wal_level = logical)';
    END IF;
END $$;

-- ==========================================
-- SECTION 2: List existing publications
-- ==========================================

-- Check for existing publications
DO $$
DECLARE
    pub_count int;
BEGIN
    SELECT count(*) INTO pub_count FROM pg_publication WHERE pubname = 'litellm_migration';

    IF pub_count > 0 THEN
        RAISE NOTICE 'Publication "litellm_migration" already exists';
        RAISE NOTICE 'Dropping existing publication...';
        EXECUTE 'DROP PUBLICATION litellm_migration';
        RAISE NOTICE '✓ Dropped existing publication';
    END IF;
END $$;

-- ==========================================
-- SECTION 3: Create publication
-- ==========================================

-- Create publication for ALL tables
-- This will replicate all tables in the database
CREATE PUBLICATION litellm_migration FOR ALL TABLES;

-- Alternative: Create publication for specific tables only
-- Uncomment below if you want to replicate only specific tables:
/*
CREATE PUBLICATION litellm_migration FOR TABLE
    "LiteLLM_VerificationToken",
    "LiteLLM_UserTable",
    "LiteLLM_TeamTable",
    "LiteLLM_TeamMembership",
    "LiteLLM_BudgetTable",
    "LiteLLM_OrganizationTable",
    "LiteLLM_OrganizationMembership",
    "LiteLLM_ProxyModelTable",
    "LiteLLM_CredentialsTable",
    "LiteLLM_SpendLogs",
    "LiteLLM_ErrorLogs",
    "LiteLLM_DailyUserSpend",
    "LiteLLM_DailyTeamSpend",
    "LiteLLM_DailyTagSpend",
    "LiteLLM_EndUserTable",
    "LiteLLM_InvitationLink",
    "LiteLLM_GuardrailsTable",
    "LiteLLM_PromptTable",
    "LiteLLM_SearchToolsTable",
    "LiteLLM_AgentsTable",
    "LiteLLM_MCPServerTable",
    "LiteLLM_SSOConfig",
    "LiteLLM_CacheConfig",
    "LiteLLM_AuditLog";
*/

RAISE NOTICE '';
RAISE NOTICE '===========================================';
RAISE NOTICE 'Publication created successfully!';
RAISE NOTICE '===========================================';

-- ==========================================
-- SECTION 4: Verify publication
-- ==========================================

-- Show publication details
SELECT
    pubname as publication_name,
    puballtables as replicates_all_tables,
    pubinsert as replicates_inserts,
    pubupdate as replicates_updates,
    pubdelete as replicates_deletes,
    pubtruncate as replicates_truncates
FROM pg_publication
WHERE pubname = 'litellm_migration';

-- List tables included in publication
SELECT
    schemaname,
    tablename
FROM pg_publication_tables
WHERE pubname = 'litellm_migration'
ORDER BY schemaname, tablename;

-- Count tables in publication
SELECT
    count(*) as tables_in_publication
FROM pg_publication_tables
WHERE pubname = 'litellm_migration';

-- ==========================================
-- SECTION 5: Display summary
-- ==========================================

DO $$
DECLARE
    table_count int;
    total_rows bigint;
BEGIN
    -- Count tables
    SELECT count(*) INTO table_count
    FROM pg_publication_tables
    WHERE pubname = 'litellm_migration';

    -- Estimate total rows (approximate)
    SELECT sum(n_live_tup) INTO total_rows
    FROM pg_stat_user_tables
    WHERE schemaname = 'public';

    RAISE NOTICE '';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Publication Summary';
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'Publication name: litellm_migration';
    RAISE NOTICE 'Tables included: %', table_count;
    RAISE NOTICE 'Estimated total rows: %', total_rows;
    RAISE NOTICE '';
    RAISE NOTICE 'What happens now:';
    RAISE NOTICE '  - All INSERT/UPDATE/DELETE operations are logged';
    RAISE NOTICE '  - WAL (Write-Ahead Log) retains these changes';
    RAISE NOTICE '  - Changes will be streamed to subscriber when connected';
    RAISE NOTICE '';
    RAISE NOTICE 'Important notes:';
    RAISE NOTICE '  - Old database continues operating normally';
    RAISE NOTICE '  - No performance impact until subscriber connects';
    RAISE NOTICE '  - WAL files will accumulate (monitor disk space)';
    RAISE NOTICE '';
    RAISE NOTICE 'Next step:';
    RAISE NOTICE '  1. Ensure new database schema is created';
    RAISE NOTICE '  2. Run 04-create-subscription.sql on NEW database';
    RAISE NOTICE '===========================================';
END $$;

-- ==========================================
-- SECTION 6: Useful monitoring queries
-- ==========================================

-- Monitor WAL generation rate
SELECT
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) as total_wal_generated;

-- Check current WAL position
SELECT pg_current_wal_lsn() as current_wal_position;

-- ==========================================
-- TROUBLESHOOTING
-- ==========================================

/*
Common issues and solutions:

1. ERROR: permission denied to create publication
   Solution: User must have CREATE privilege on database
   Fix: GRANT CREATE ON DATABASE litellmdb TO your_user;

2. ERROR: publication "litellm_migration" already exists
   Solution: Drop existing publication first
   Fix: DROP PUBLICATION litellm_migration;

3. ERROR: logical replication requires wal_level to be logical
   Solution: Enable logical replication (requires restart)
   Fix: Run 02-enable-logical-replication.sql

4. Tables not appearing in pg_publication_tables
   Solution: Ensure tables exist and user has SELECT privilege
   Fix: GRANT SELECT ON ALL TABLES IN SCHEMA public TO your_user;

To drop the publication if needed:
   DROP PUBLICATION IF EXISTS litellm_migration CASCADE;
*/
