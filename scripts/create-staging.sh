#!/bin/bash
#
# create-staging.sh
# Clone production WordPress environment to staging
#
# Usage: ./create-staging.sh
#

set -e  # Exit on error

# Load environment variables
if [ ! -f "../.env" ]; then
    echo "ERROR: .env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

# Source from parent directory
source ../.env

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================"
echo "  WordPress Staging Environment Creator"
echo "================================================"
echo ""

# Check if production is running
echo -n "Checking if production is running... "
if ! docker ps | grep -q "${INSTANCE}-wordpress"; then
    echo -e "${RED}FAILED${NC}"
    echo "ERROR: Production WordPress container is not running."
    echo "Start production first with: docker compose up -d"
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Check disk space
echo -n "Checking disk space... "
AVAILABLE=$(df /home/${INSTANCE} | tail -1 | awk '{print $4}')
REQUIRED=$(du -s /home/${INSTANCE}/.srv/wordpress /home/${INSTANCE}/.srv/database 2>/dev/null | awk '{sum+=$1} END {print sum}')
if [ "$AVAILABLE" -lt "$((REQUIRED * 2))" ]; then
    echo -e "${YELLOW}WARNING${NC}"
    echo "Low disk space. Available: ${AVAILABLE}KB, Required: ~$((REQUIRED * 2))KB"
    read -p "Continue anyway? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 1
    fi
else
    echo -e "${GREEN}OK${NC}"
fi

# Check if staging already exists
if docker ps -a | grep -q "${INSTANCE}-staging-wordpress"; then
    echo ""
    echo -e "${YELLOW}WARNING: Staging containers already exist.${NC}"
    echo "This will stop and recreate them, destroying any existing staging data."
    read -p "Continue? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        exit 1
    fi
    echo "Stopping staging containers..."
    docker compose stop staging-wordpress staging-db staging-wpcli staging-phpmyadmin 2>/dev/null || true
fi

echo ""
echo "Creating staging directory structure..."
mkdir -p /home/${INSTANCE}/.srv/staging/{wordpress,database,log,log/mysql}

echo "Cloning WordPress files to staging..."
rsync -av --delete /home/${INSTANCE}/.srv/wordpress/ /home/${INSTANCE}/.srv/staging/wordpress/
echo -e "${GREEN}Files cloned successfully${NC}"

echo ""
echo "Exporting production database..."
DUMP_FILE="/tmp/prod-dump-$(date +%s).sql"
docker exec ${INSTANCE}-db mysqldump \
    -u root \
    -p${MYSQL_ROOT_PASSWORD} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    ${WORDPRESS_DB_NAME} > "${DUMP_FILE}"

if [ ! -s "${DUMP_FILE}" ]; then
    echo -e "${RED}ERROR: Database export failed or is empty${NC}"
    exit 1
fi
echo -e "${GREEN}Database exported successfully${NC}"

echo ""
echo "Starting staging database..."
docker compose up -d staging-db
echo "Waiting for staging database to be ready..."
sleep 10

# Wait for database to be ready
until docker exec ${INSTANCE}-staging-db mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; do
    echo -n "."
    sleep 2
done
echo ""
echo -e "${GREEN}Staging database is ready${NC}"

echo "Importing database to staging..."
docker exec -i ${INSTANCE}-staging-db mysql \
    -u root \
    -p${MYSQL_ROOT_PASSWORD} \
    ${WORDPRESS_DB_NAME} < "${DUMP_FILE}"
echo -e "${GREEN}Database imported successfully${NC}"

# Cleanup temp dump file
rm -f "${DUMP_FILE}"

echo ""
echo "Starting staging WordPress..."
docker compose up -d staging-wordpress staging-wpcli staging-phpmyadmin

echo "Waiting for WordPress to be ready..."
sleep 5

echo ""
echo "Updating URLs in staging database..."
docker compose run --rm staging-wpcli wp search-replace \
    "${PROD_URL}" \
    "${STAGING_URL}" \
    --all-tables \
    --report-changed-only || true

echo ""
echo "Setting file permissions..."
docker compose exec staging-wordpress chown -R www-data:www-data /var/www/html 2>/dev/null || true
docker compose exec staging-wordpress find /var/www/html -type d -exec chmod 755 {} \; 2>/dev/null || true
docker compose exec staging-wordpress find /var/www/html -type f -exec chmod 644 {} \; 2>/dev/null || true
docker compose exec staging-wordpress chmod 600 /var/www/html/wp-config.php 2>/dev/null || true

echo ""
echo "Disabling search engine indexing in staging..."
docker compose run --rm staging-wpcli wp option update blog_public 0 2>/dev/null || true

echo ""
echo "================================================"
echo -e "  ${GREEN}Staging Environment Created Successfully!${NC}"
echo "================================================"
echo ""
echo "Access URLs:"
echo "  WordPress:   ${STAGING_URL}"
echo "  phpMyAdmin:  http://$(hostname -I | awk '{print $1}'):${STAGING_PMA_ACCESS_PORT}"
echo ""
echo "Container Status:"
docker ps --filter "name=${INSTANCE}-staging" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Next steps:"
echo "  1. Access staging at ${STAGING_URL}"
echo "  2. Make and test your changes"
echo "  3. When ready, promote to production with: ./promote-staging.sh"
echo ""
