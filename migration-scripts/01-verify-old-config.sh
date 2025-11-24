#!/bin/bash
#
# Script: 01-verify-old-config.sh
# Purpose: Extract and verify configuration from old LiteLLM instance
# Usage: ./01-verify-old-config.sh
#

set -e

echo "=========================================="
echo "LiteLLM Migration - Configuration Verification"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create output file for configuration
CONFIG_FILE="old-instance-config.env"
echo "# Old LiteLLM Instance Configuration" > "$CONFIG_FILE"
echo "# Generated: $(date)" >> "$CONFIG_FILE"
echo "" >> "$CONFIG_FILE"

echo "Step 1: Collecting old instance configuration..."
echo ""

# Function to prompt for configuration
prompt_config() {
    local var_name=$1
    local prompt_text=$2
    local is_secret=$3

    echo -e "${YELLOW}$prompt_text${NC}"
    if [ "$is_secret" = "true" ]; then
        read -s -p "Value (hidden): " value
        echo ""
    else
        read -p "Value: " value
    fi

    echo "$var_name=\"$value\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}✓ Saved $var_name${NC}"
    echo ""
}

# Collect critical configuration
echo "=== CRITICAL Configuration ==="
echo ""

prompt_config "OLD_LITELLM_SALT_KEY" "Enter LITELLM_SALT_KEY from old instance (CRITICAL!):" "true"
prompt_config "OLD_LITELLM_MASTER_KEY" "Enter LITELLM_MASTER_KEY from old instance:" "true"

echo ""
echo "=== Database Configuration ==="
echo ""

prompt_config "OLD_DB_HOST" "Enter old database host (e.g., old-db.region.rds.amazonaws.com):" "false"
prompt_config "OLD_DB_PORT" "Enter old database port (default: 5432):" "false"
prompt_config "OLD_DB_NAME" "Enter old database name (default: litellmdb):" "false"
prompt_config "OLD_DB_USER" "Enter old database username:" "false"
prompt_config "OLD_DB_PASSWORD" "Enter old database password:" "true"

echo ""
echo "=== New Database Configuration ==="
echo ""

prompt_config "NEW_DB_HOST" "Enter new database host:" "false"
prompt_config "NEW_DB_PORT" "Enter new database port (default: 5432):" "false"
prompt_config "NEW_DB_NAME" "Enter new database name (default: litellmdb):" "false"
prompt_config "NEW_DB_USER" "Enter new database username:" "false"
prompt_config "NEW_DB_PASSWORD" "Enter new database password:" "true"

echo ""
echo "=== LiteLLM Version Information ==="
echo ""

prompt_config "OLD_LITELLM_VERSION" "Enter LiteLLM version/branch from old instance (e.g., premium-side commit hash):" "false"

# Set default values if not provided
sed -i 's/OLD_DB_PORT=""/OLD_DB_PORT="5432"/' "$CONFIG_FILE" 2>/dev/null || true
sed -i 's/NEW_DB_PORT=""/NEW_DB_PORT="5432"/' "$CONFIG_FILE" 2>/dev/null || true
sed -i 's/OLD_DB_NAME=""/OLD_DB_NAME="litellmdb"/' "$CONFIG_FILE" 2>/dev/null || true
sed -i 's/NEW_DB_NAME=""/NEW_DB_NAME="litellmdb"/' "$CONFIG_FILE" 2>/dev/null || true

echo ""
echo "=========================================="
echo "Step 2: Verifying database connectivity..."
echo "=========================================="
echo ""

# Source the config file
source "$CONFIG_FILE"

# Test old database connection
echo "Testing connection to OLD database..."
if psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully connected to old database${NC}"
else
    echo -e "${RED}✗ Failed to connect to old database${NC}"
    echo "Please verify credentials and try again"
    exit 1
fi

echo ""

# Test new database connection
echo "Testing connection to NEW database..."
if psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully connected to new database${NC}"
else
    echo -e "${RED}✗ Failed to connect to new database${NC}"
    echo "Please verify credentials and try again"
    exit 1
fi

echo ""
echo "=========================================="
echo "Step 3: Checking database compatibility..."
echo "=========================================="
echo ""

# Get PostgreSQL versions
OLD_PG_VERSION=$(psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" -t -c "SHOW server_version;" | xargs)
NEW_PG_VERSION=$(psql "postgresql://$NEW_DB_USER:$NEW_DB_PASSWORD@$NEW_DB_HOST:$NEW_DB_PORT/$NEW_DB_NAME?sslmode=require" -t -c "SHOW server_version;" | xargs)

echo "Old database PostgreSQL version: $OLD_PG_VERSION"
echo "New database PostgreSQL version: $NEW_PG_VERSION"

echo "OLD_PG_VERSION=\"$OLD_PG_VERSION\"" >> "$CONFIG_FILE"
echo "NEW_PG_VERSION=\"$NEW_PG_VERSION\"" >> "$CONFIG_FILE"

echo ""
echo "=========================================="
echo "Step 4: Collecting database statistics..."
echo "=========================================="
echo ""

# Get table counts from old database
echo "Collecting table statistics from old database..."
OLD_STATS=$(psql "postgresql://$OLD_DB_USER:$OLD_DB_PASSWORD@$OLD_DB_HOST:$OLD_DB_PORT/$OLD_DB_NAME?sslmode=require" -t -c "
SELECT
    schemaname || '.' || tablename as table_name,
    n_live_tup as row_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;
" | grep -E "LiteLLM_" || true)

echo "$OLD_STATS" > old-database-stats.txt
echo -e "${GREEN}✓ Statistics saved to old-database-stats.txt${NC}"

# Display key tables
echo ""
echo "Key table row counts in old database:"
echo "----------------------------------------"
cat old-database-stats.txt | head -20

echo ""
echo "=========================================="
echo "Configuration verification complete!"
echo "=========================================="
echo ""
echo -e "${GREEN}Configuration saved to: $CONFIG_FILE${NC}"
echo -e "${GREEN}Database statistics saved to: old-database-stats.txt${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT SECURITY NOTE:${NC}"
echo "The file $CONFIG_FILE contains sensitive credentials."
echo "Keep it secure and delete it after migration is complete."
echo ""
echo -e "${YELLOW}CRITICAL REMINDER:${NC}"
echo "Make sure to set these values on your new Azure deployment:"
echo "  azd env set LITELLM_SALT_KEY \"<value from OLD_LITELLM_SALT_KEY>\""
echo "  azd env set LITELLM_MASTER_KEY \"<value from OLD_LITELLM_MASTER_KEY>\""
echo ""
echo "Next step: Run 02-enable-logical-replication.sql on the old database"
