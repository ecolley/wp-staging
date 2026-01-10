#!/bin/bash
#
# staging-status.sh
# Display status of production and staging environments
#
# Usage: ./staging-status.sh
#

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
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "================================================"
echo "  WordPress Staging Environment Status"
echo "================================================"
echo ""

# Instance Information
echo -e "${BLUE}Instance: ${INSTANCE}${NC}"
echo -e "${BLUE}Hostname: $(hostname)${NC}"
echo -e "${BLUE}IP Address: $(hostname -I | awk '{print $1}')${NC}"
echo ""

# Container Status
echo "Container Status:"
echo "================================================"
docker ps -a --filter "name=${INSTANCE}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null

echo ""
echo "Access URLs:"
echo "================================================"
echo -e "Production:"
echo -e "  WordPress:   ${CYAN}${PROD_URL}${NC}"
echo -e "  phpMyAdmin:  ${CYAN}http://$(hostname -I | awk '{print $1}'):${PMA_ACCESS_PORT}${NC}"
echo -e "  Database:    ${CYAN}$(hostname -I | awk '{print $1}'):${DB_PORT}${NC}"
echo ""
echo -e "Staging:"
echo -e "  WordPress:   ${CYAN}${STAGING_URL}${NC}"
echo -e "  phpMyAdmin:  ${CYAN}http://$(hostname -I | awk '{print $1}'):${STAGING_PMA_ACCESS_PORT}${NC}"
echo -e "  Database:    ${CYAN}$(hostname -I | awk '{print $1}'):${STAGING_DB_PORT}${NC}"

echo ""
echo "Disk Usage:"
echo "================================================"
if [ -d "/home/${INSTANCE}/.srv/wordpress" ]; then
    PROD_WP_SIZE=$(du -sh /home/${INSTANCE}/.srv/wordpress 2>/dev/null | cut -f1)
    echo -e "Production WordPress: ${PROD_WP_SIZE}"
else
    echo -e "Production WordPress: ${YELLOW}Not found${NC}"
fi

if [ -d "/home/${INSTANCE}/.srv/database" ]; then
    PROD_DB_SIZE=$(du -sh /home/${INSTANCE}/.srv/database 2>/dev/null | cut -f1)
    echo -e "Production Database:  ${PROD_DB_SIZE}"
else
    echo -e "Production Database:  ${YELLOW}Not found${NC}"
fi

if [ -d "/home/${INSTANCE}/.srv/staging/wordpress" ]; then
    STAGING_WP_SIZE=$(du -sh /home/${INSTANCE}/.srv/staging/wordpress 2>/dev/null | cut -f1)
    echo -e "Staging WordPress:    ${STAGING_WP_SIZE}"
else
    echo -e "Staging WordPress:    ${YELLOW}Not found${NC}"
fi

if [ -d "/home/${INSTANCE}/.srv/staging/database" ]; then
    STAGING_DB_SIZE=$(du -sh /home/${INSTANCE}/.srv/staging/database 2>/dev/null | cut -f1)
    echo -e "Staging Database:     ${STAGING_DB_SIZE}"
else
    echo -e "Staging Database:     ${YELLOW}Not found${NC}"
fi

if [ -d "/home/${INSTANCE}/.srv/backups" ]; then
    BACKUPS_SIZE=$(du -sh /home/${INSTANCE}/.srv/backups 2>/dev/null | cut -f1)
    BACKUP_COUNT=$(ls -1 /home/${INSTANCE}/.srv/backups 2>/dev/null | wc -l)
    echo -e "Backups (${BACKUP_COUNT}):         ${BACKUPS_SIZE}"
else
    echo -e "Backups:              ${YELLOW}Not found${NC}"
fi

TOTAL_SIZE=$(du -sh /home/${INSTANCE}/.srv 2>/dev/null | cut -f1)
echo -e "Total:                ${TOTAL_SIZE}"

# Available Backups
echo ""
echo "Available Backups:"
echo "================================================"
if [ -d "/home/${INSTANCE}/.srv/backups" ] && [ "$(ls -A /home/${INSTANCE}/.srv/backups)" ]; then
    ls -lht /home/${INSTANCE}/.srv/backups/ 2>/dev/null | grep "^d" | awk '{print "  " $9 " - " $5 " - " $6 " " $7 " " $8}'
    echo ""
    LATEST_BACKUP=$(ls -t /home/${INSTANCE}/.srv/backups/ 2>/dev/null | head -1)
    if [ ! -z "$LATEST_BACKUP" ]; then
        echo -e "Latest backup: ${GREEN}${LATEST_BACKUP}${NC}"
    fi
else
    echo "  No backups found"
fi

# WordPress Info (if WP-CLI is available)
echo ""
echo "WordPress Information:"
echo "================================================"

if docker ps | grep -q "${INSTANCE}-wordpress"; then
    WP_VERSION=$(docker compose run --rm wpcli wp core version 2>/dev/null || echo "N/A")
    echo -e "Production Version: ${WP_VERSION}"

    POST_COUNT=$(docker compose run --rm wpcli wp post list --post_type=post --format=count 2>/dev/null || echo "N/A")
    echo -e "Production Posts:   ${POST_COUNT}"

    USER_COUNT=$(docker compose run --rm wpcli wp user list --format=count 2>/dev/null || echo "N/A")
    echo -e "Production Users:   ${USER_COUNT}"

    ACTIVE_THEME=$(docker compose run --rm wpcli wp theme list --status=active --field=name 2>/dev/null || echo "N/A")
    echo -e "Production Theme:   ${ACTIVE_THEME}"
else
    echo -e "${YELLOW}Production not running${NC}"
fi

if docker ps | grep -q "${INSTANCE}-staging-wordpress"; then
    STAGING_WP_VERSION=$(docker compose run --rm staging-wpcli wp core version 2>/dev/null || echo "N/A")
    echo -e "Staging Version:    ${STAGING_WP_VERSION}"

    STAGING_POST_COUNT=$(docker compose run --rm staging-wpcli wp post list --post_type=post --format=count 2>/dev/null || echo "N/A")
    echo -e "Staging Posts:      ${STAGING_POST_COUNT}"
else
    echo -e "${YELLOW}Staging not running${NC}"
fi

# Health Checks
echo ""
echo "Health Checks:"
echo "================================================"

# Check production
echo -n "Production WordPress: "
if curl -f -s -o /dev/null "${PROD_URL}" 2>/dev/null; then
    echo -e "${GREEN}Accessible${NC}"
else
    echo -e "${RED}Not accessible${NC}"
fi

# Check staging
echo -n "Staging WordPress:    "
if docker ps | grep -q "${INSTANCE}-staging-wordpress"; then
    if curl -f -s -o /dev/null "${STAGING_URL}" 2>/dev/null; then
        echo -e "${GREEN}Accessible${NC}"
    else
        echo -e "${YELLOW}Running but not accessible${NC}"
    fi
else
    echo -e "${YELLOW}Not running${NC}"
fi

# Check production database
echo -n "Production Database:  "
if docker exec ${INSTANCE}-db mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; then
    echo -e "${GREEN}Responsive${NC}"
else
    echo -e "${RED}Not responsive${NC}"
fi

# Check staging database
echo -n "Staging Database:     "
if docker ps | grep -q "${INSTANCE}-staging-db"; then
    if docker exec ${INSTANCE}-staging-db mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD} --silent 2>/dev/null; then
        echo -e "${GREEN}Responsive${NC}"
    else
        echo -e "${YELLOW}Running but not responsive${NC}"
    fi
else
    echo -e "${YELLOW}Not running${NC}"
fi

echo ""
echo "================================================"
echo ""
echo "Quick Commands:"
echo "  Create staging:   ./create-staging.sh"
echo "  Backup production: ./backup-production.sh"
echo "  Promote staging:  ./promote-staging.sh"
echo "  Rollback:         ./rollback-production.sh TIMESTAMP"
echo ""
