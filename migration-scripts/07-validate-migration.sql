--
-- Script: 07-validate-migration.sql
-- Purpose: Validate data integrity and completeness after migration
-- Target: NEW DATABASE (destination) - Compare with OLD database statistics
--
-- Prerequisites:
--   - Migration completed
--   - Sequences synchronized (06-sync-sequences.sql)
--   - New LiteLLM instance started
--
-- Usage:
--   psql "postgresql://user:pass@new-db-host:5432/litellmdb?sslmode=require" -f 07-validate-migration.sql
--

\timing off
\pset border 2

-- ==========================================
-- SECTION 1: Environment check
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Migration Validation Report'
\echo '==========================================='
\echo ''

SELECT
    current_database() as database_name,
    version() as postgresql_version,
    now() as validation_timestamp;

-- ==========================================
-- SECTION 2: Table existence check
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Table Existence Check'
\echo '==========================================='
\echo ''

-- Count LiteLLM tables
DO $$
DECLARE
    table_count int;
    expected_min_tables int := 20;  -- Minimum expected LiteLLM tables
BEGIN
    SELECT count(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name LIKE 'LiteLLM_%';

    RAISE NOTICE 'Found % LiteLLM tables', table_count;

    IF table_count >= expected_min_tables THEN
        RAISE NOTICE '✓ Table count looks good (expected: >= %)', expected_min_tables;
    ELSE
        RAISE WARNING '✗ Expected at least % tables, found %', expected_min_tables, table_count;
    END IF;
    RAISE NOTICE '';
END $$;

-- List all LiteLLM tables
SELECT
    schemaname,
    tablename,
    n_live_tup as row_count,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    CASE
        WHEN n_live_tup = 0 THEN '⚠ Empty'
        WHEN n_live_tup < 10 THEN '  Few rows'
        ELSE '✓ Has data'
    END as status
FROM pg_stat_user_tables
WHERE tablename LIKE 'LiteLLM_%'
ORDER BY n_live_tup DESC;

-- ==========================================
-- SECTION 3: Critical tables row count
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Critical Tables Row Count'
\echo '==========================================='
\echo ''

-- Display row counts for critical tables
SELECT
    'LiteLLM_UserTable' as table_name,
    count(*) as row_count,
    'Users' as description
FROM "LiteLLM_UserTable"
UNION ALL
SELECT
    'LiteLLM_TeamTable',
    count(*),
    'Teams'
FROM "LiteLLM_TeamTable"
UNION ALL
SELECT
    'LiteLLM_VerificationToken',
    count(*),
    'API Keys'
FROM "LiteLLM_VerificationToken"
UNION ALL
SELECT
    'LiteLLM_ProxyModelTable',
    count(*),
    'Models'
FROM "LiteLLM_ProxyModelTable"
UNION ALL
SELECT
    'LiteLLM_BudgetTable',
    count(*),
    'Budgets'
FROM "LiteLLM_BudgetTable"
UNION ALL
SELECT
    'LiteLLM_OrganizationTable',
    count(*),
    'Organizations'
FROM "LiteLLM_OrganizationTable"
UNION ALL
SELECT
    'LiteLLM_SpendLogs',
    count(*),
    'Spend Logs (historical)'
FROM "LiteLLM_SpendLogs"
UNION ALL
SELECT
    'LiteLLM_ErrorLogs',
    count(*),
    'Error Logs (historical)'
FROM "LiteLLM_ErrorLogs";

-- ==========================================
-- SECTION 4: Data integrity checks
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Data Integrity Checks'
\echo '==========================================='
\echo ''

-- Check for NULL values in critical columns
DO $$
DECLARE
    null_count int;
    issues_found boolean := false;
BEGIN
    RAISE NOTICE 'Checking for NULL values in critical columns...';
    RAISE NOTICE '';

    -- Check LiteLLM_UserTable.user_id
    SELECT count(*) INTO null_count FROM "LiteLLM_UserTable" WHERE user_id IS NULL;
    IF null_count > 0 THEN
        RAISE WARNING '✗ Found % NULL user_id in LiteLLM_UserTable', null_count;
        issues_found := true;
    ELSE
        RAISE NOTICE '✓ LiteLLM_UserTable.user_id: No NULLs';
    END IF;

    -- Check LiteLLM_TeamTable.team_id
    SELECT count(*) INTO null_count FROM "LiteLLM_TeamTable" WHERE team_id IS NULL;
    IF null_count > 0 THEN
        RAISE WARNING '✗ Found % NULL team_id in LiteLLM_TeamTable', null_count;
        issues_found := true;
    ELSE
        RAISE NOTICE '✓ LiteLLM_TeamTable.team_id: No NULLs';
    END IF;

    -- Check LiteLLM_VerificationToken.token
    SELECT count(*) INTO null_count FROM "LiteLLM_VerificationToken" WHERE token IS NULL;
    IF null_count > 0 THEN
        RAISE WARNING '✗ Found % NULL token in LiteLLM_VerificationToken', null_count;
        issues_found := true;
    ELSE
        RAISE NOTICE '✓ LiteLLM_VerificationToken.token: No NULLs';
    END IF;

    RAISE NOTICE '';
    IF NOT issues_found THEN
        RAISE NOTICE '✓ All integrity checks passed';
    ELSE
        RAISE WARNING '⚠ Some integrity issues found - review warnings above';
    END IF;
END $$;

-- ==========================================
-- SECTION 5: Relationship integrity
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Relationship Integrity Checks'
\echo '==========================================='
\echo ''

-- Check for orphaned team memberships
SELECT
    count(*) as orphaned_memberships,
    CASE
        WHEN count(*) = 0 THEN '✓ No orphaned memberships'
        ELSE '✗ Found orphaned team memberships'
    END as status
FROM "LiteLLM_TeamMembership" tm
WHERE NOT EXISTS (
    SELECT 1 FROM "LiteLLM_UserTable" u WHERE u.user_id = tm.user_id
)
OR NOT EXISTS (
    SELECT 1 FROM "LiteLLM_TeamTable" t WHERE t.team_id = tm.team_id
);

-- Check for API keys without users
SELECT
    count(*) as keys_without_users,
    CASE
        WHEN count(*) = 0 THEN '✓ All API keys have valid users'
        ELSE '⚠ Some API keys have no user reference'
    END as status
FROM "LiteLLM_VerificationToken" vt
WHERE vt.user_id IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM "LiteLLM_UserTable" u WHERE u.user_id = vt.user_id
);

-- ==========================================
-- SECTION 6: Encrypted data validation
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Encrypted Data Validation'
\echo '==========================================='
\echo ''

-- Check if model API keys are encrypted (should have enc_ prefix or be encrypted)
DO $$
DECLARE
    model_count int;
    encrypted_count int;
BEGIN
    SELECT count(*) INTO model_count FROM "LiteLLM_ProxyModelTable";

    IF model_count > 0 THEN
        RAISE NOTICE 'Found % models in LiteLLM_ProxyModelTable', model_count;
        RAISE NOTICE '';
        RAISE NOTICE 'CRITICAL: Test model API key decryption';
        RAISE NOTICE '';
        RAISE NOTICE 'To verify LITELLM_SALT_KEY is correct:';
        RAISE NOTICE '  1. Start the new LiteLLM instance';
        RAISE NOTICE '  2. Try to make an API call through the proxy';
        RAISE NOTICE '  3. Check logs for decryption errors';
        RAISE NOTICE '';
        RAISE NOTICE 'If you see "Error decrypting value" errors:';
        RAISE NOTICE '  ✗ LITELLM_SALT_KEY does not match old instance';
        RAISE NOTICE '  → Fix: Set correct LITELLM_SALT_KEY and redeploy';
        RAISE NOTICE '';
        RAISE NOTICE 'If API calls work correctly:';
        RAISE NOTICE '  ✓ LITELLM_SALT_KEY is correct';
    ELSE
        RAISE NOTICE 'No models configured yet';
    END IF;
END $$;

-- ==========================================
-- SECTION 7: Sequence validation
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Sequence Validation'
\echo '==========================================='
\echo ''

-- Verify sequences are properly set
SELECT
    s.sequencename,
    s.last_value as current_value,
    (SELECT max_id FROM (
        SELECT COALESCE(MAX((t.tableoid::regclass::text || '.' || quote_ident(a.attname))::text), '0')::bigint as max_id
        FROM pg_class c
        JOIN pg_attribute a ON a.attrelid = c.oid
        JOIN pg_depend d ON d.refobjid = c.oid AND d.refobjsubid = a.attnum
        JOIN pg_class s2 ON s2.oid = d.objid
        WHERE s2.relname = s.sequencename
        AND c.relkind = 'r'
    ) sub) as table_max_id,
    CASE
        WHEN s.last_value > COALESCE((SELECT max_id FROM (
            SELECT COALESCE(MAX((t.tableoid::regclass::text || '.' || quote_ident(a.attname))::text), '0')::bigint as max_id
            FROM pg_class c
            JOIN pg_attribute a ON a.attrelid = c.oid
            JOIN pg_depend d ON d.refobjid = c.oid AND d.refobjsubid = a.attnum
            JOIN pg_class s2 ON s2.oid = d.objid
            WHERE s2.relname = s.sequencename
            AND c.relkind = 'r'
        ) sub), 0) THEN '✓ OK'
        ELSE '⚠ Check'
    END as status
FROM pg_sequences s
WHERE s.schemaname = 'public'
ORDER BY s.sequencename
LIMIT 10;

-- ==========================================
-- SECTION 8: Database statistics comparison
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Database Statistics (NEW Database)'
\echo '==========================================='
\echo ''

-- Overall database statistics
SELECT
    pg_size_pretty(pg_database_size(current_database())) as database_size,
    (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public') as total_tables,
    (SELECT count(*) FROM pg_stat_user_tables WHERE schemaname = 'public') as tables_with_stats,
    (SELECT sum(n_live_tup) FROM pg_stat_user_tables WHERE schemaname = 'public') as total_rows;

-- Top 10 largest tables
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    n_live_tup as row_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- ==========================================
-- SECTION 9: Compare with old database stats
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Comparison with Old Database'
\echo '==========================================='
\echo ''

DO $$
BEGIN
    RAISE NOTICE 'To compare with old database statistics:';
    RAISE NOTICE '';
    RAISE NOTICE '1. Check the file: old-database-stats.txt';
    RAISE NOTICE '   (created by 01-verify-old-config.sh)';
    RAISE NOTICE '';
    RAISE NOTICE '2. Compare row counts for key tables:';
    RAISE NOTICE '   - LiteLLM_UserTable';
    RAISE NOTICE '   - LiteLLM_TeamTable';
    RAISE NOTICE '   - LiteLLM_VerificationToken';
    RAISE NOTICE '   - LiteLLM_ProxyModelTable';
    RAISE NOTICE '   - LiteLLM_SpendLogs';
    RAISE NOTICE '';
    RAISE NOTICE '3. Row counts should match or be very close';
    RAISE NOTICE '   (small differences OK if old instance was still active)';
    RAISE NOTICE '';
END $$;

-- ==========================================
-- SECTION 10: Application-level validation
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Application-Level Validation Checklist'
\echo '==========================================='
\echo ''

DO $$
BEGIN
    RAISE NOTICE 'Manual validation steps:';
    RAISE NOTICE '';
    RAISE NOTICE '✓ Database migration:';
    RAISE NOTICE '  [ ] All tables present';
    RAISE NOTICE '  [ ] Row counts match old database';
    RAISE NOTICE '  [ ] No orphaned relationships';
    RAISE NOTICE '  [ ] Sequences properly synchronized';
    RAISE NOTICE '';
    RAISE NOTICE '✓ LiteLLM application:';
    RAISE NOTICE '  [ ] New instance starts successfully';
    RAISE NOTICE '  [ ] No decryption errors in logs';
    RAISE NOTICE '  [ ] Can access Admin UI (/ui)';
    RAISE NOTICE '  [ ] Can access Swagger UI (/)';
    RAISE NOTICE '';
    RAISE NOTICE '✓ Authentication:';
    RAISE NOTICE '  [ ] Existing API keys work';
    RAISE NOTICE '  [ ] Can authenticate with master key';
    RAISE NOTICE '  [ ] User login works (if using SSO)';
    RAISE NOTICE '';
    RAISE NOTICE '✓ Functionality:';
    RAISE NOTICE '  [ ] Can make API calls through proxy';
    RAISE NOTICE '  [ ] Model configurations load correctly';
    RAISE NOTICE '  [ ] Budget enforcement works';
    RAISE NOTICE '  [ ] Rate limiting works';
    RAISE NOTICE '  [ ] Spend tracking updates';
    RAISE NOTICE '';
    RAISE NOTICE '✓ Teams & permissions:';
    RAISE NOTICE '  [ ] Team memberships preserved';
    RAISE NOTICE '  [ ] User permissions work correctly';
    RAISE NOTICE '  [ ] Organization hierarchy intact';
    RAISE NOTICE '';
END $$;

-- ==========================================
-- SECTION 11: Sample data verification
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Sample Data Verification'
\echo '==========================================='
\echo ''

-- Show sample users (first 5)
\echo 'Sample Users (first 5):'
SELECT
    user_id,
    user_email,
    user_role,
    created_at
FROM "LiteLLM_UserTable"
ORDER BY created_at DESC
LIMIT 5;

-- Show sample API keys (first 5, token truncated)
\echo ''
\echo 'Sample API Keys (first 5):'
SELECT
    left(token, 20) || '...' as token_preview,
    user_id,
    team_id,
    budget_id,
    created_at
FROM "LiteLLM_VerificationToken"
ORDER BY created_at DESC
LIMIT 5;

-- Show sample models (first 5)
\echo ''
\echo 'Sample Models (first 5):'
SELECT
    model_id,
    model_name,
    litellm_model,
    created_at
FROM "LiteLLM_ProxyModelTable"
ORDER BY created_at DESC
LIMIT 5;

-- ==========================================
-- SECTION 12: Final validation summary
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Validation Summary'
\echo '==========================================='
\echo ''

DO $$
DECLARE
    table_count int;
    user_count int;
    model_count int;
    key_count int;
BEGIN
    SELECT count(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name LIKE 'LiteLLM_%';

    SELECT count(*) INTO user_count FROM "LiteLLM_UserTable";
    SELECT count(*) INTO model_count FROM "LiteLLM_ProxyModelTable";
    SELECT count(*) INTO key_count FROM "LiteLLM_VerificationToken";

    RAISE NOTICE 'Migration Statistics:';
    RAISE NOTICE '  Tables: %', table_count;
    RAISE NOTICE '  Users: %', user_count;
    RAISE NOTICE '  Models: %', model_count;
    RAISE NOTICE '  API Keys: %', key_count;
    RAISE NOTICE '';

    IF table_count >= 20 AND user_count > 0 THEN
        RAISE NOTICE '✓ Database migration appears successful!';
        RAISE NOTICE '';
        RAISE NOTICE 'Next steps:';
        RAISE NOTICE '  1. Complete application-level validation checklist';
        RAISE NOTICE '  2. Test critical workflows';
        RAISE NOTICE '  3. Monitor for 24-48 hours';
        RAISE NOTICE '  4. Keep old database as backup for 7-30 days';
        RAISE NOTICE '  5. After validation, run cleanup commands in 06-sync-sequences.sql';
    ELSE
        RAISE WARNING '⚠ Migration may be incomplete - review details above';
        RAISE WARNING '';
        RAISE WARNING 'Issues to investigate:';
        IF table_count < 20 THEN
            RAISE WARNING '  - Table count lower than expected';
        END IF;
        IF user_count = 0 THEN
            RAISE WARNING '  - No users found in database';
        END IF;
    END IF;
    RAISE NOTICE '';
END $$;

-- ==========================================
-- SECTION 13: Monitoring recommendations
-- ==========================================

\echo ''
\echo '==========================================='
\echo 'Post-Migration Monitoring'
\echo '==========================================='
\echo ''

DO $$
BEGIN
    RAISE NOTICE 'Monitor these metrics over the next 24-48 hours:';
    RAISE NOTICE '';
    RAISE NOTICE '1. Application logs:';
    RAISE NOTICE '   - Check for errors in Container App logs';
    RAISE NOTICE '   - Watch for decryption errors';
    RAISE NOTICE '   - Monitor database connection issues';
    RAISE NOTICE '';
    RAISE NOTICE '2. Database performance:';
    RAISE NOTICE '   - Monitor query performance';
    RAISE NOTICE '   - Check connection pool usage';
    RAISE NOTICE '   - Watch for slow queries';
    RAISE NOTICE '';
    RAISE NOTICE '3. API functionality:';
    RAISE NOTICE '   - Test API calls regularly';
    RAISE NOTICE '   - Verify spend tracking updates';
    RAISE NOTICE '   - Confirm rate limiting works';
    RAISE NOTICE '';
    RAISE NOTICE '4. User reports:';
    RAISE NOTICE '   - Monitor for user-reported issues';
    RAISE NOTICE '   - Verify existing integrations work';
    RAISE NOTICE '   - Check that scheduled jobs run';
    RAISE NOTICE '';
    RAISE NOTICE 'Keep old database running as backup until:';
    RAISE NOTICE '  - All validation checks pass';
    RAISE NOTICE '  - No issues found for 48+ hours';
    RAISE NOTICE '  - Users confirm everything works';
    RAISE NOTICE '';
END $$;

\echo ''
\echo '==========================================='
\echo 'Validation Complete'
\echo '==========================================='
\echo ''
