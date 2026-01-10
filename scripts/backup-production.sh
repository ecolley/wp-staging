#!/bin/bash
#
# backup-production.sh
# Create a timestamped backup of production WordPress
#
# Usage: ./backup-production.sh
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
echo "  WordPress Production Backup"
echo "================================================"
echo ""

# Check if production is running
echo -n "Checking if production is running... "
if ! docker ps | grep -q "${INSTANCE}-wordpress"; then
    echo -e "${RED}FAILED${NC}"
    echo "ERROR: Production WordPress container is not running."
    exit 1
fi
echo -e "${GREEN}OK${NC}"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/home/${INSTANCE}/.srv/backups/${TIMESTAMP}"

echo "Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

echo ""
echo "Exporting production database..."
docker exec ${INSTANCE}-db mysqldump \
    -u root \
    -p${MYSQL_ROOT_PASSWORD} \
    --single-transaction \
    --quick \
    --lock-tables=false \
    ${WORDPRESS_DB_NAME} > "${BACKUP_DIR}/database.sql"

if [ ! -s "${BACKUP_DIR}/database.sql" ]; then
    echo -e "${RED}ERROR: Database backup failed or is empty${NC}"
    rm -rf "${BACKUP_DIR}"
    exit 1
fi
echo -e "${GREEN}Database backed up successfully${NC}"

echo ""
echo "Copying WordPress files..."
rsync -a /home/${INSTANCE}/.srv/wordpress/ "${BACKUP_DIR}/wordpress/"
echo -e "${GREEN}Files backed up successfully${NC}"

echo ""
echo "Creating backup metadata..."
cat > "${BACKUP_DIR}/backup-info.txt" <<EOF
WordPress Production Backup
============================
Timestamp: ${TIMESTAMP}
Date: $(date)
Instance: ${INSTANCE}
Production URL: ${PROD_URL}

Backup Contents:
-----------------
WordPress Files: $(du -sh ${BACKUP_DIR}/wordpress/ | cut -f1)
Database Size: $(du -sh ${BACKUP_DIR}/database.sql | cut -f1)
Total Backup Size: $(du -sh ${BACKUP_DIR} | cut -f1)

File Count: $(find ${BACKUP_DIR}/wordpress -type f | wc -l) files

Database Info:
--------------
Database Name: ${WORDPRESS_DB_NAME}
Database User: ${WORDPRESS_DB_USER}

Post Count: $(docker compose run --rm wpcli wp post list --format=count 2>/dev/null || echo "N/A")
User Count: $(docker compose run --rm wpcli wp user list --format=count 2>/dev/null || echo "N/A")
Theme: $(docker compose run --rm wpcli wp theme list --status=active --field=name 2>/dev/null || echo "N/A")

Restore Instructions:
---------------------
To restore this backup, run:
    ./rollback-production.sh ${TIMESTAMP}
EOF

echo -e "${GREEN}Metadata created${NC}"

# Clean up old backups based on retention policy
echo ""
echo "Checking backup retention policy..."

# Remove backups older than BACKUP_RETENTION_DAYS
if [ ! -z "$BACKUP_RETENTION_DAYS" ] && [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
    OLD_BACKUPS=$(find /home/${INSTANCE}/.srv/backups/ -maxdepth 1 -type d -mtime +${BACKUP_RETENTION_DAYS} | grep -v "^/home/${INSTANCE}/.srv/backups/$")
    if [ ! -z "$OLD_BACKUPS" ]; then
        echo "Removing backups older than ${BACKUP_RETENTION_DAYS} days:"
        echo "$OLD_BACKUPS" | while read backup; do
            echo "  - $(basename $backup)"
            rm -rf "$backup"
        done
    fi
fi

# Remove excess backups if MAX_BACKUPS is set
if [ ! -z "$MAX_BACKUPS" ] && [ "$MAX_BACKUPS" -gt 0 ]; then
    BACKUP_COUNT=$(find /home/${INSTANCE}/.srv/backups/ -maxdepth 1 -type d | grep -v "^/home/${INSTANCE}/.srv/backups/$" | wc -l)
    if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
        EXCESS=$((BACKUP_COUNT - MAX_BACKUPS))
        echo "Removing ${EXCESS} oldest backups (keeping ${MAX_BACKUPS} total):"
        find /home/${INSTANCE}/.srv/backups/ -maxdepth 1 -type d | grep -v "^/home/${INSTANCE}/.srv/backups/$" | sort | head -n $EXCESS | while read backup; do
            echo "  - $(basename $backup)"
            rm -rf "$backup"
        done
    fi
fi

echo ""
echo "================================================"
echo -e "  ${GREEN}Backup Created Successfully!${NC}"
echo "================================================"
echo ""
echo "Backup Details:"
echo "  Timestamp: ${TIMESTAMP}"
echo "  Location: ${BACKUP_DIR}"
echo "  Size: $(du -sh ${BACKUP_DIR} | cut -f1)"
echo ""
echo "Available Backups:"
ls -lh /home/${INSTANCE}/.srv/backups/ | grep "^d" | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "To restore this backup, run:"
echo "  ./rollback-production.sh ${TIMESTAMP}"
echo ""
