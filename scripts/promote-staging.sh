#!/bin/bash
#
# promote-staging.sh
# Promote staging environment to production with automatic backup
#
# Usage: ./promote-staging.sh
#

set -e  # Exit on error

# Load environment variables
if [ ! -f "../.env" ]; then
    echo "ERROR: .env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

source ../.env

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "  WordPress Staging Promotion"
echo "================================================"
echo ""

# Check if staging is running
echo -n "Checking if staging is running... "
if ! docker ps | grep -q "${INSTANCE}-staging-wordpress"; then
    echo -e "${RED}FAILED${NC}"
    echo "ERROR: Staging WordPress container is not running."
    echo "Create staging first with: ./create-staging.sh"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Verify staging is accessible
echo -n "Verifying staging is accessible... "
if ! curl -f -s -o /dev/null "${STAGING_URL}" 2>/dev/null; then
    echo -e "${YELLOW}WARNING${NC}"
    echo "Staging URL ${STAGING_URL} is not accessible via curl."
    read -p "Continue anyway? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 1
    fi
else
    echo -e "${GREEN}OK${NC}"
fi

echo ""
echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              ⚠️  WARNING  ⚠️                   ║${NC}"
echo -e "${RED}║                                                ║${NC}"
echo -e "${RED}║  This will replace PRODUCTION with STAGING!   ║${NC}"
echo -e "${RED}║                                                ║${NC}"
echo -e "${RED}║  - Production will be backed up first         ║${NC}"
echo -e "${RED}║  - All production changes will be lost        ║${NC}"
echo -e "${RED}║  - Staging will become the new production     ║${NC}"
echo -e "${RED}║                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "Production URL: ${PROD_URL}"
echo "Staging URL: ${STAGING_URL}"
echo ""
read -p "Type 'PROMOTE' to confirm: " CONFIRM

if [ "$CONFIRM" != "PROMOTE" ]; then
    echo "Promotion cancelled."
    exit 0
fi

echo ""
echo "Step 1/8: Creating production backup..."
./backup-production.sh
LATEST_BACKUP=$(ls -t /home/${INSTANCE}/.srv/backups/ | head -1)
echo -e "${GREEN}Backup created: ${LATEST_BACKUP}${NC}"

echo ""
echo "Step 2/8: Stopping production services..."
docker compose stop wordpress db wpcli phpmyadmin

echo ""
echo "Step 3/8: Moving production data to temporary location..."
mv /home/${INSTANCE}/.srv/wordpress /home/${INSTANCE}/.srv/wordpress.old
mv /home/${INSTANCE}/.srv/database /home/${INSTANCE}/.srv/database.old
echo -e "${GREEN}Production data moved to .old${NC}"

echo ""
echo "Step 4/8: Stopping staging services..."
docker compose stop staging-wordpress staging-db staging-wpcli staging-phpmyadmin

echo ""
echo "Step 5/8: Copying staging files to production..."
rsync -av /home/${INSTANCE}/.srv/staging/wordpress/ /home/${INSTANCE}/.srv/wordpress/
echo -e "${GREEN}Files copied${NC}"

echo ""
echo "Step 6/8: Exporting staging database..."
DUMP_FILE="/tmp/staging-dump-$(date +%s).sql"
docker compose start staging-db
sleep 5
docker exec ${INSTANCE}-staging-db mysqldump \
    -u root \
    -p${MYSQL_ROOT_PASSWORD} \
    --single-transaction \
    ${WORDPRESS_DB_NAME} > "${DUMP_FILE}"

if [ ! -s "${DUMP_FILE}" ]; then
    echo -e "${RED}ERROR: Staging database export failed${NC}"
    echo "Restoring production from backup..."
    ./rollback-production.sh "${LATEST_BACKUP}"
    exit 1
fi
echo -e "${GREEN}Staging database exported${NC}"

echo ""
echo "Step 7/8: Importing to production database..."
# Initialize production database
mkdir -p /home/${INSTANCE}/.srv/database
docker compose start db
echo "Waiting for production database..."
sleep 10

until docker exec ${INSTANCE}-db mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; do
    echo -n "."
    sleep 2
done
echo ""

docker exec -i ${INSTANCE}-db mysql \
    -u root \
    -p${MYSQL_ROOT_PASSWORD} \
    ${WORDPRESS_DB_NAME} < "${DUMP_FILE}"
rm -f "${DUMP_FILE}"
echo -e "${GREEN}Database imported${NC}"

echo ""
echo "Step 8/8: Updating URLs and starting production..."
docker compose start wordpress wpcli phpmyadmin

sleep 5

# Update URLs in production
echo "Updating WordPress URLs from ${STAGING_URL} to ${PROD_URL}..."

# Try wp-cli first
if docker compose run --rm wpcli wp search-replace \
    "${STAGING_URL}" \
    "${PROD_URL}" \
    --all-tables \
    --report-changed-only 2>/dev/null; then
    echo -e "${GREEN}URLs updated via wp-cli${NC}"
else
    echo -e "${YELLOW}wp-cli failed, using direct database update...${NC}"
    # Fallback to direct MySQL UPDATE commands
    docker exec ${INSTANCE}-db mysql -u root -p${MYSQL_ROOT_PASSWORD} ${WORDPRESS_DB_NAME} -e "
        UPDATE wp_options SET option_value = '${PROD_URL}' WHERE option_name IN ('siteurl', 'home');
        UPDATE wp_posts SET post_content = REPLACE(post_content, '${STAGING_URL}', '${PROD_URL}');
        UPDATE wp_posts SET guid = REPLACE(guid, '${STAGING_URL}', '${PROD_URL}');
        UPDATE wp_postmeta SET meta_value = REPLACE(meta_value, '${STAGING_URL}', '${PROD_URL}');
    " 2>&1 | grep -v "Warning"
    echo -e "${GREEN}URLs updated via direct database commands${NC}"
fi

# Verify the URLs were actually updated
CURRENT_URL=$(docker exec ${INSTANCE}-db mysql -u root -p${MYSQL_ROOT_PASSWORD} ${WORDPRESS_DB_NAME} -se "SELECT option_value FROM wp_options WHERE option_name = 'siteurl';" 2>/dev/null | grep -v "Warning")
if [ "$CURRENT_URL" = "${PROD_URL}" ]; then
    echo -e "${GREEN}URL update verified successfully${NC}"
else
    echo -e "${RED}ERROR: URL update failed! Current URL: ${CURRENT_URL}${NC}"
    echo "Attempting automatic rollback..."
    ./rollback-production.sh "${LATEST_BACKUP}"
    exit 1
fi

# Re-enable search engine indexing
docker compose run --rm wpcli wp option update blog_public 1 2>/dev/null || \
    docker exec ${INSTANCE}-db mysql -u root -p${MYSQL_ROOT_PASSWORD} ${WORDPRESS_DB_NAME} -e "UPDATE wp_options SET option_value = '1' WHERE option_name = 'blog_public';" 2>&1 | grep -v "Warning"

echo ""
echo "Verifying production..."
sleep 3

if ! curl -f -s -o /dev/null "${PROD_URL}" 2>/dev/null; then
    echo -e "${RED}ERROR: Production verification failed!${NC}"
    echo "Production is not accessible at ${PROD_URL}"
    echo ""
    echo "Attempting automatic rollback..."
    ./rollback-production.sh "${LATEST_BACKUP}"
    exit 1
fi

echo -e "${GREEN}Production is accessible${NC}"

echo ""
echo "Cleaning up old production data..."
rm -rf /home/${INSTANCE}/.srv/wordpress.old
rm -rf /home/${INSTANCE}/.srv/database.old
echo -e "${GREEN}Cleanup complete${NC}"

echo ""
echo "================================================"
echo -e "  ${GREEN}Promotion Successful!${NC}"
echo "================================================"
echo ""
echo "Production Status:"
docker ps --filter "name=${INSTANCE}-wordpress\|${INSTANCE}-db\|${INSTANCE}-pma" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Production URL: ${PROD_URL}"
echo "Backup saved as: ${LATEST_BACKUP}"
echo ""
echo "Note: Staging environment is still available for further testing."
echo "To recreate staging from the new production, run: ./create-staging.sh"
echo ""
echo "If you need to rollback, run:"
echo "  ./rollback-production.sh ${LATEST_BACKUP}"
echo ""
