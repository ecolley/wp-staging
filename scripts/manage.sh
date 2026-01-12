#!/bin/bash
#
# manage.sh
# WordPress Environment Manager - Menu-driven interface
#
# Usage: ./manage.sh
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
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Function to display header
show_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}║          ${BOLD}WordPress Environment Manager${NC}${BLUE}             ║${NC}"
    echo -e "${BLUE}║                                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to check container status
check_container_status() {
    local container=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "${GREEN}RUNNING${NC}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        echo -e "${YELLOW}STOPPED${NC}"
    else
        echo -e "${RED}NOT FOUND${NC}"
    fi
}

# Function to check URL accessibility
check_url() {
    local url=$1
    if curl -f -s -o /dev/null "$url" 2>/dev/null; then
        echo -e "${GREEN}ACCESSIBLE${NC}"
    else
        echo -e "${RED}NOT ACCESSIBLE${NC}"
    fi
}

# Function to display environment status
show_status() {
    echo -e "${CYAN}${BOLD}Production Environment:${NC}"
    echo -e "  Instance Name:    ${INSTANCE}"
    echo -e "  URL:              ${PROD_URL}"
    echo -ne "  WordPress:        "
    check_container_status "${INSTANCE}-wordpress"
    echo -ne "  Database:         "
    check_container_status "${INSTANCE}-db"
    echo -ne "  phpMyAdmin:       "
    check_container_status "${INSTANCE}-pma"
    echo -ne "  Web Access:       "
    check_url "${PROD_URL}"
    echo ""

    echo -e "${MAGENTA}${BOLD}Staging Environment:${NC}"
    echo -e "  URL:              ${STAGING_URL}"
    echo -ne "  WordPress:        "
    check_container_status "${INSTANCE}-staging-wordpress"
    echo -ne "  Database:         "
    check_container_status "${INSTANCE}-staging-db"
    echo -ne "  phpMyAdmin:       "
    check_container_status "${INSTANCE}-staging-pma"
    echo -ne "  Web Access:       "
    check_url "${STAGING_URL}"
    echo ""

    echo -e "${YELLOW}${BOLD}Backups:${NC}"
    if [ -d "/home/${INSTANCE}/.srv/backups" ]; then
        BACKUP_COUNT=$(find /home/${INSTANCE}/.srv/backups/ -maxdepth 1 -type d | grep -v "^/home/${INSTANCE}/.srv/backups/$" | wc -l || echo "0")
        echo -e "  Available:        ${BACKUP_COUNT} backup(s)"
        if [ "$BACKUP_COUNT" -gt 0 ]; then
            LATEST=$(ls -t /home/${INSTANCE}/.srv/backups/ | head -1)
            echo -e "  Latest:           ${LATEST}"
        fi
    else
        echo -e "  Available:        ${RED}No backups${NC}"
    fi
    echo ""
}

# Function to display main menu
show_menu() {
    echo -e "${BOLD}Available Operations:${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) View detailed status"
    echo -e "  ${GREEN}2${NC}) Create/Update staging environment"
    echo -e "  ${GREEN}3${NC}) Backup production"
    echo -e "  ${GREEN}4${NC}) Promote staging to production"
    echo -e "  ${GREEN}5${NC}) Rollback production"
    echo -e "  ${GREEN}6${NC}) View staging status details"
    echo ""
    echo -e "  ${RED}0${NC}) Exit"
    echo ""
}

# Function to pause and wait for user
pause() {
    echo ""
    read -p "Press Enter to continue..."
}

# Function to run staging status
run_staging_status() {
    show_header
    echo -e "${CYAN}${BOLD}Staging Environment Status${NC}"
    echo ""
    ./staging-status.sh
    pause
}

# Function to create staging
run_create_staging() {
    show_header
    echo -e "${CYAN}${BOLD}Create/Update Staging Environment${NC}"
    echo ""
    ./create-staging.sh
    pause
}

# Function to backup production
run_backup() {
    show_header
    echo -e "${CYAN}${BOLD}Backup Production${NC}"
    echo ""
    ./backup-production.sh
    pause
}

# Function to promote staging
run_promote() {
    show_header
    echo -e "${CYAN}${BOLD}Promote Staging to Production${NC}"
    echo ""
    echo -e "${RED}${BOLD}WARNING: This will replace production with staging!${NC}"
    echo ""
    ./promote-staging.sh
    pause
}

# Function to rollback production
run_rollback() {
    show_header
    echo -e "${CYAN}${BOLD}Rollback Production${NC}"
    echo ""

    if [ ! -d "/home/${INSTANCE}/.srv/backups" ]; then
        echo -e "${RED}ERROR: No backups directory found${NC}"
        pause
        return
    fi

    BACKUP_COUNT=$(find /home/${INSTANCE}/.srv/backups/ -maxdepth 1 -type d | grep -v "^/home/${INSTANCE}/.srv/backups/$" | wc -l || echo "0")

    if [ "$BACKUP_COUNT" -eq 0 ]; then
        echo -e "${RED}ERROR: No backups available${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}Available backups:${NC}"
    echo ""

    BACKUPS=($(ls -t /home/${INSTANCE}/.srv/backups/))
    for i in "${!BACKUPS[@]}"; do
        BACKUP="${BACKUPS[$i]}"
        SIZE=$(du -sh "/home/${INSTANCE}/.srv/backups/${BACKUP}" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}$((i+1))${NC}) ${BACKUP} (${SIZE})"
    done

    echo ""
    echo -e "  ${RED}0${NC}) Cancel"
    echo ""
    read -p "Select backup to restore: " choice

    if [ "$choice" -eq 0 ] 2>/dev/null; then
        echo "Rollback cancelled"
        pause
        return
    fi

    if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#BACKUPS[@]}" ]; then
        SELECTED_BACKUP="${BACKUPS[$((choice-1))]}"
        echo ""
        echo -e "${YELLOW}Selected: ${SELECTED_BACKUP}${NC}"
        echo ""
        ./rollback-production.sh "${SELECTED_BACKUP}"
    else
        echo -e "${RED}Invalid selection${NC}"
    fi

    pause
}

# Main loop
while true; do
    show_header
    show_status
    show_menu

    read -p "Select option: " choice

    case $choice in
        1)
            run_staging_status
            ;;
        2)
            run_create_staging
            ;;
        3)
            run_backup
            ;;
        4)
            run_promote
            ;;
        5)
            run_rollback
            ;;
        6)
            run_staging_status
            ;;
        0)
            clear
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            sleep 1
            ;;
    esac
done
