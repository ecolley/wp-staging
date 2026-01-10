#!/bin/bash
#
# setup-lxc.sh
# Prepare a fresh Debian LXC for WordPress with staging
#
# Prerequisites:
#   - Fresh Debian LXC
#   - Docker installed
#   - Passwordless root SSH enabled
#
# Usage: ./setup-lxc.sh
#

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "  WordPress Staging - LXC Setup"
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Verify prerequisites
echo "Checking prerequisites..."
echo ""

# Check for Docker
echo -n "Checking Docker... "
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | tr -d ',')
    echo -e "${GREEN}OK${NC} (${DOCKER_VERSION})"
else
    echo -e "${RED}NOT FOUND${NC}"
    echo "Please install Docker first."
    exit 1
fi

# Check for Docker Compose
echo -n "Checking Docker Compose... "
if command -v docker compose &> /dev/null || command -v docker-compose &> /dev/null; then
    if command -v docker compose &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    else
        COMPOSE_VERSION=$(docker-compose --version | cut -d ' ' -f4 | tr -d ',')
    fi
    echo -e "${GREEN}OK${NC} (${COMPOSE_VERSION})"
else
    echo -e "${RED}NOT FOUND${NC}"
    echo "Please install Docker Compose first."
    exit 1
fi

echo ""
echo "Step 1/6: Installing essential packages..."
apt-get update
apt-get install -y \
    git \
    curl \
    wget \
    rsync \
    vim \
    htop \
    ca-certificates \
    gnupg \
    lsb-release

echo -e "${GREEN}Packages installed${NC}"

echo ""
echo "Step 2/6: Configuring Git..."

# Check if git is already configured
if [ -z "$(git config --global user.name)" ] || [ -z "$(git config --global user.email)" ]; then
    echo "Git needs to be configured."
    read -p "Enter your Git name: " GIT_NAME
    read -p "Enter your Git email: " GIT_EMAIL

    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    echo -e "${GREEN}Git configured${NC}"
else
    echo -e "${GREEN}Git already configured${NC}"
    echo "Name:  $(git config --global user.name)"
    echo "Email: $(git config --global user.email)"
fi

# Set recommended git settings
git config --global init.defaultBranch main
git config --global pull.rebase false

echo ""
echo "Step 3/6: Installing Claude Code..."

# Check if Claude Code is already installed
if command -v claude &> /dev/null; then
    echo -e "${YELLOW}Claude Code already installed${NC}"
    CURRENT_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    echo "Current version: ${CURRENT_VERSION}"
    read -p "Reinstall/update? (y/N): " REINSTALL
    if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
        echo "Skipping Claude Code installation"
    else
        curl -fsSL https://install.anthropic.com | sh
        echo -e "${GREEN}Claude Code updated${NC}"
    fi
else
    curl -fsSL https://install.anthropic.com | sh
    echo -e "${GREEN}Claude Code installed${NC}"
fi

# Add Claude Code to PATH if not already there
if ! grep -q 'claude' ~/.bashrc; then
    echo '' >> ~/.bashrc
    echo '# Claude Code' >> ~/.bashrc
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

echo ""
echo "Step 4/6: Creating project directory structure..."

# Ask for instance name
read -p "Enter instance name (default: sitename): " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-sitename}

# Create directory structure
mkdir -p /home/${INSTANCE_NAME}
cd /home/${INSTANCE_NAME}

echo -e "${GREEN}Directory created: /home/${INSTANCE_NAME}${NC}"

echo ""
echo "Step 5/6: Cloning wp-staging repository..."
echo "This will clone the repository into the current directory."
echo "Repository: https://github.com/ecolley/wp-staging.git"
echo ""
read -p "Clone now? (Y/n): " CLONE
if [ "$CLONE" != "n" ] && [ "$CLONE" != "N" ]; then
    if [ -d ".git" ]; then
        echo -e "${YELLOW}Git repository already exists${NC}"
    else
        git clone https://github.com/ecolley/wp-staging.git .
        echo -e "${GREEN}Repository cloned${NC}"
    fi
else
    echo "Skipping repository clone. You can clone manually later with:"
    echo "  cd /home/${INSTANCE_NAME} && git clone https://github.com/ecolley/wp-staging.git ."
fi

echo ""
echo "Step 6/6: Creating environment configuration..."

if [ -f ".env" ]; then
    echo -e "${YELLOW}.env file already exists${NC}"
    read -p "Overwrite? (y/N): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "Keeping existing .env file"
    else
        cp .env.example .env
        echo -e "${GREEN}.env created from template${NC}"
    fi
elif [ -f ".env.example" ]; then
    cp .env.example .env

    # Update instance name in .env
    sed -i "s/INSTANCE=sitename/INSTANCE=${INSTANCE_NAME}/" .env

    # Get IP address
    IP_ADDRESS=$(hostname -I | awk '{print $1}')

    # Update URLs with IP address
    sed -i "s|PROD_URL=http://10.10.10.141:8081|PROD_URL=http://${IP_ADDRESS}:8081|" .env
    sed -i "s|STAGING_URL=http://10.10.10.141:8181|STAGING_URL=http://${IP_ADDRESS}:8181|" .env

    echo -e "${GREEN}.env created and configured${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Update passwords in .env before starting!${NC}"
else
    echo -e "${YELLOW}.env.example not found. Manual configuration needed.${NC}"
fi

echo ""
echo "================================================"
echo -e "  ${GREEN}LXC Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Summary:"
echo "  Instance:     ${INSTANCE_NAME}"
echo "  Location:     /home/${INSTANCE_NAME}"
echo "  IP Address:   $(hostname -I | awk '{print $1}')"
echo ""
echo "Next steps:"
echo "  1. Review and update .env file:"
echo "     ${BLUE}vim /home/${INSTANCE_NAME}/.env${NC}"
echo ""
echo "  2. Update database passwords (SECURITY!):"
echo "     - WORDPRESS_DB_PASSWORD"
echo "     - MYSQL_ROOT_PASSWORD"
echo ""
echo "  3. Start production environment:"
echo "     ${BLUE}cd /home/${INSTANCE_NAME} && docker compose up -d${NC}"
echo ""
echo "  4. Access WordPress at:"
echo "     ${BLUE}http://$(hostname -I | awk '{print $1}'):8081${NC}"
echo ""
echo "  5. Create staging environment:"
echo "     ${BLUE}cd /home/${INSTANCE_NAME}/scripts && ./create-staging.sh${NC}"
echo ""
echo "  6. Check status anytime:"
echo "     ${BLUE}cd /home/${INSTANCE_NAME}/scripts && ./staging-status.sh${NC}"
echo ""
echo "Documentation:"
echo "  README: /home/${INSTANCE_NAME}/README.md"
echo ""
echo "Claude Code:"
echo "  Start session: ${BLUE}claude${NC}"
echo "  Note: You may need to source ~/.bashrc or start a new shell"
echo ""
