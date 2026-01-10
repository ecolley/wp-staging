#!/bin/bash
#
# rollback-production.sh
# Restore production from a backup
#
# Usage: ./rollback-production.sh [TIMESTAMP]
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
echo "  WordPress Production Rollback"
echo "================================================"
echo ""

# Check if backup timestamp was provided
if [ -z "$1" ]; then
    echo "Available backups:"
    echo ""
    ls -lh /home/${INSTANCE}/.srv/backups/ 2>/dev/null | grep "^d" | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
    echo "Usage: $0 TIMESTAMP"
    echo "Example: $0 20260110-143022"
    exit 1
fi

BACKUP_TIMESTAMP="$1"
BACKUP_DIR="/home/${INSTANCE}/.srv/backups/${BACKUP_TIMESTAMP}"

# Verify backup exists
if [ ! -d "${BACKUP_DIR}" ]; then
    echo -e "${RED}ERROR: Backup directory not found: ${BACKUP_DIR}${NC}"
    echo ""
    echo "Available backups:"
    ls -lh /home/${INSTANCE}/.srv/backups/ 2>/dev/null | grep "^d" | awk '{print "  " $9 " (" $5 ")"}'
    exit 1
fi

# Verify backup is complete
if [ ! -f "${BACKUP_DIR}/database.sql" ]; then
    echo -e "${RED}ERROR: Database backup file missing: ${BACKUP_DIR}/database.sql${NC}"
    exit 1
fi

if [ ! -d "${BACKUP_DIR}/wordpress" ]; then
    echo -e "${RED}ERROR: WordPress files backup missing: ${BACKUP_DIR}/wordpress${NC}"
    exit 1
fi

echo "Backup Information:"
echo "================================================"
cat "${BACKUP_DIR}/backup-info.txt" 2>/dev/null || echo "Backup info file not found"
echo "================================================"
echo ""

echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              ⚠️  WARNING  ⚠️                   ║${NC}"
echo -e "${RED}║                                                ║${NC}"
echo -e "${RED}║  This will REPLACE current production with    ║${NC}"
echo -e "${RED}║  the backup from ${BACKUP_TIMESTAMP}              ║${NC}"
echo -e "${RED}║                                                ║${NC}"
echo -e "${RED}║  All current production data will be lost!    ║${NC}"
echo -e "${RED}║                                                ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
echo ""
read -p "Type 'ROLLBACK' to confirm: " CONFIRM

if [ "$CONFIRM" != "ROLLBACK" ]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
echo "Step 1/6: Stopping production services..."
docker compose stop wordpress db wpcli phpmyadmin

echo ""
echo "Step 2/6: Creating safety backup of current state..."
SAFETY_BACKUP="/home/${INSTANCE}/.srv/wordpress.rollback-temp"
SAFETY_DB="/home/${INSTANCE}/.srv/database.rollback-temp"

if [ -d "/home/${INSTANCE}/.srv/wordpress" ]; then
    mv /home/${INSTANCE}/.srv/wordpress "${SAFETY_BACKUP}"
    echo -e "${GREEN}WordPress files moved to temporary location${NC}"
fi

if [ -d "/home/${INSTANCE}/.srv/database" ]; then
    mv /home/${INSTANCE}/.srv/database "${SAFETY_DB}"
    echo -e "${GREEN}Database files moved to temporary location${NC}"
fi

echo ""
echo "Step 3/6: Restoring WordPress files from backup..."
mkdir -p /home/${INSTANCE}/.srv/wordpress
rsync -av "${BACKUP_DIR}/wordpress/" /home/${INSTANCE}/.srv/wordpress/
echo -e "${GREEN}Files restored${NC}"

echo ""
echo "Step 4/6: Restoring database from backup..."
mkdir -p /home/${INSTANCE}/.srv/database
docker compose start db
echo "Waiting for database to initialize..."
sleep 10

until docker exec ${INSTANCE}-db mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; do
    echo -n "."
    sleep 2
done
echo ""

docker exec -i ${INSTANCE}-db mysql \
    -u root \
    -p${MYSQL_ROOT_PASSWORD} \
    ${WORDPRESS_DB_NAME} < "${BACKUP_DIR}/database.sql"
echo -e "${GREEN}Database restored${NC}"

echo ""
echo "Step 5/6: Starting production services..."
docker compose start wordpress wpcli phpmyadmin
sleep 5

echo ""
echo "Step 6/6: Verifying production..."
if ! curl -f -s -o /dev/null "${PROD_URL}" 2>/dev/null; then
    echo -e "${YELLOW}WARNING: Production verification failed${NC}"
    echo "Production may not be accessible at ${PROD_URL}"
    echo ""
    read -p "Continue with cleanup? (y/N): " continue
    if [ "$continue" != "y" ] && [ "$continue" != "Y" ]; then
        echo "Rollback complete but cleanup skipped."
        echo "Temporary files remain at:"
        echo "  ${SAFETY_BACKUP}"
        echo "  ${SAFETY_DB}"
        exit 1
    fi
else
    echo -e "${GREEN}Production is accessible${NC}"
fi

echo ""
echo "Cleaning up temporary files..."
rm -rf "${SAFETY_BACKUP}"
rm -rf "${SAFETY_DB}"
echo -e "${GREEN}Cleanup complete${NC}"

echo ""
echo "================================================"
echo -e "  ${GREEN}Rollback Successful!${NC}"
echo "================================================"
echo ""
echo "Production has been restored to backup: ${BACKUP_TIMESTAMP}"
echo ""
echo "Production Status:"
docker ps --filter "name=${INSTANCE}-wordpress\|${INSTANCE}-db\|${INSTANCE}-pma" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Production URL: ${PROD_URL}"
echo ""
echo "Next steps:"
echo "  1. Verify production is working correctly"
echo "  2. If needed, recreate staging with: ./create-staging.sh"
echo ""
