# WordPress with Staging Environment

A production-ready WordPress deployment using Docker Compose with built-in staging environment, backup management, and promotion workflows.

## Features

- **Production & Staging Environments**: Run both environments simultaneously on the same server
- **One-Command Cloning**: Clone production to staging with a single script
- **Automatic Backups**: Automatic backup before promotion with configurable retention
- **Safe Promotion**: Promote staging to production with verification and automatic rollback on failure
- **Easy Rollback**: Restore production from any backup timestamp
- **URL Management**: Automatic WordPress URL search-replace using WP-CLI
- **Status Monitoring**: View status, disk usage, and health of all environments

## Quick Start

### Prerequisites

- Debian LXC container (or any Debian-based system)
- Docker and Docker Compose installed
- Root or sudo access
- Passwordless SSH (optional, for remote management)

### Installation

1. **Automated Setup** (Recommended for new LXC):
   ```bash
   wget https://raw.githubusercontent.com/ecolley/wp-staging/main/setup-lxc.sh
   chmod +x setup-lxc.sh
   ./setup-lxc.sh
   ```

2. **Manual Setup**:
   ```bash
   # Clone the repository
   cd /home
   git clone https://github.com/ecolley/wp-staging.git
   cd wp-staging

   # Configure environment
   cp .env.example .env
   vim .env  # Update settings, especially passwords!
   ```

### Initial Deployment

1. **Start Production Environment**:
   ```bash
   docker compose up -d
   ```

2. **Access WordPress**:
   - Navigate to `http://YOUR_IP:8081`
   - Complete WordPress installation
   - Configure your site

3. **Verify Production**:
   ```bash
   cd scripts
   ./staging-status.sh
   ```

## Usage

### Creating a Staging Environment

Clone production to staging for testing changes:

```bash
cd scripts
./create-staging.sh
```

This will:
- Clone all WordPress files from production
- Export and import production database
- Update URLs in staging database
- Start staging containers
- Disable search engine indexing in staging

Access staging at: `http://YOUR_IP:8181`

### Making Changes in Staging

1. Access staging WordPress: `http://YOUR_IP:8181/wp-admin`
2. Make your changes (themes, plugins, content, etc.)
3. Test thoroughly
4. When ready, promote to production

### Promoting Staging to Production

Replace production with staging (creates backup first):

```bash
cd scripts
./promote-staging.sh
```

This will:
1. Create automatic backup of production
2. Stop production services
3. Copy staging files to production
4. Import staging database to production
5. Update URLs for production
6. Verify production is accessible
7. Automatically rollback if verification fails

**Note**: Type `PROMOTE` when prompted to confirm.

### Rolling Back Production

Restore production from a backup:

```bash
cd scripts

# List available backups
ls -lh /home/${INSTANCE}/.srv/backups/

# Rollback to specific backup
./rollback-production.sh 20260110-143022
```

**Note**: Type `ROLLBACK` when prompted to confirm.

### Creating Manual Backups

```bash
cd scripts
./backup-production.sh
```

Backups include:
- Complete WordPress files
- Full database export
- Metadata file with backup information

### Checking Status

View comprehensive status of all environments:

```bash
cd scripts
./staging-status.sh
```

Displays:
- Container status and uptime
- Access URLs
- Disk usage
- Available backups
- WordPress information
- Health checks

## Configuration

### Environment Variables (.env)

| Variable | Description | Example |
|----------|-------------|---------|
| `INSTANCE` | Unique instance identifier | `sitename` |
| `WP_PORT` | Production WordPress port | `8081` |
| `DB_PORT` | Production database port | `3324` |
| `PMA_ACCESS_PORT` | Production phpMyAdmin port | `8824` |
| `STAGING_WP_PORT` | Staging WordPress port | `8181` |
| `STAGING_DB_PORT` | Staging database port | `3424` |
| `STAGING_PMA_ACCESS_PORT` | Staging phpMyAdmin port | `8924` |
| `WORDPRESS_DB_NAME` | Database name | `wordpress` |
| `WORDPRESS_DB_USER` | Database user | `wordpress` |
| `WORDPRESS_DB_PASSWORD` | Database password | `changeme` |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | `changeme` |
| `PROD_URL` | Production WordPress URL | `http://10.10.10.141:8081` |
| `STAGING_URL` | Staging WordPress URL | `http://10.10.10.141:8181` |
| `BACKUP_RETENTION_DAYS` | Days to keep backups | `7` |
| `MAX_BACKUPS` | Maximum number of backups | `10` |

### Ports

Default port allocation (offset staging by 100):

| Service | Production | Staging |
|---------|-----------|---------|
| WordPress | 8081 | 8181 |
| MySQL | 3324 | 3424 |
| phpMyAdmin | 8824 | 8924 |

### Custom PHP Settings (custom.ini)

The `custom.ini` file configures PHP for both environments:

```ini
file_uploads = On
memory_limit = 3072M           # 3GB for large media
upload_max_filesize = 3072M
post_max_size = 3072M
max_execution_time = 1200      # 20 minutes
max_input_vars = 2000
```

## Directory Structure

```
/home/${INSTANCE}/
├── docker-compose.yml          # Container definitions
├── .env                        # Configuration (not in git)
├── .env.example               # Configuration template
├── custom.ini                 # PHP configuration
├── setup-lxc.sh              # LXC setup script
├── README.md                 # This file
├── scripts/
│   ├── create-staging.sh     # Clone production to staging
│   ├── backup-production.sh  # Create production backup
│   ├── promote-staging.sh    # Promote staging to production
│   ├── rollback-production.sh # Restore from backup
│   └── staging-status.sh     # View environment status
└── .srv/                     # Data (not in git)
    ├── wordpress/            # Production WordPress files
    ├── database/             # Production MySQL data
    ├── log/                  # Production logs
    ├── staging/
    │   ├── wordpress/        # Staging WordPress files
    │   ├── database/         # Staging MySQL data
    │   └── log/              # Staging logs
    └── backups/
        └── YYYYMMDD-HHMMSS/  # Timestamped backups
            ├── wordpress/    # Backup WordPress files
            ├── database.sql  # Backup database
            └── backup-info.txt # Backup metadata
```

## Workflows

### Typical Change Workflow

```bash
# 1. Create staging from current production
cd scripts
./create-staging.sh

# 2. Make changes in staging
# Access http://YOUR_IP:8181/wp-admin

# 3. Test thoroughly in staging

# 4. When ready, promote to production
./promote-staging.sh
# Type: PROMOTE

# 5. Verify production
# Access http://YOUR_IP:8081
```

### Emergency Rollback Workflow

```bash
# 1. List available backups
ls -lh /home/${INSTANCE}/.srv/backups/

# 2. Rollback to previous state
cd scripts
./rollback-production.sh 20260110-143022
# Type: ROLLBACK

# 3. Verify production is restored
./staging-status.sh
```

### Regular Backup Workflow

```bash
# Create manual backup before major changes
cd scripts
./backup-production.sh

# Optional: Set up automatic daily backups with cron
# Add to crontab:
# 0 2 * * * cd /home/${INSTANCE}/scripts && ./backup-production.sh
```

## Docker Commands

### Starting Services

```bash
# Start production only
docker compose up -d wordpress db phpmyadmin wpcli

# Start staging only
docker compose up -d staging-wordpress staging-db staging-phpmyadmin staging-wpcli

# Start everything
docker compose up -d
```

### Stopping Services

```bash
# Stop production
docker compose stop wordpress db phpmyadmin wpcli

# Stop staging
docker compose stop staging-wordpress staging-db staging-phpmyadmin staging-wpcli

# Stop everything
docker compose down
```

### Viewing Logs

```bash
# Production WordPress logs
docker compose logs -f wordpress

# Staging WordPress logs
docker compose logs -f staging-wordpress

# Database logs
docker compose logs -f db
```

### WP-CLI Commands

```bash
# Production
docker compose run --rm wpcli wp [command]

# Staging
docker compose run --rm staging-wpcli wp [command]

# Examples:
docker compose run --rm wpcli wp user list
docker compose run --rm wpcli wp plugin list
docker compose run --rm wpcli wp theme list
docker compose run --rm wpcli wp post list
```

## Security Considerations

### Required Actions

1. **Change Default Passwords**: Update database passwords in `.env`
2. **Firewall Staging Ports**: Restrict staging ports to trusted IPs
3. **Secure phpMyAdmin**: Consider adding authentication or restricting access
4. **Regular Backups**: Enable automatic backups via cron
5. **Keep Updated**: Regularly update WordPress, plugins, and Docker images

### Staging Security

Staging is automatically configured with:
- Search engine indexing disabled (`blog_public = 0`)
- Same database credentials as production (for easier cloning)

**Recommendation**: Add firewall rules to restrict staging access:

```bash
# Example: Allow only from specific IP
ufw allow from YOUR_IP to any port 8181
ufw allow from YOUR_IP to any port 8924
```

### Backup Security

- Backups are stored on the same server (not offsite)
- Consider copying critical backups to remote storage
- Backups contain sensitive data; protect accordingly

## Troubleshooting

### Staging Creation Fails

**Problem**: Database export/import fails

**Solution**:
```bash
# Check production database is running
docker ps | grep db

# Check database connectivity
docker exec ${INSTANCE}-db mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD}

# Check disk space
df -h
```

### Promotion Fails

**Problem**: Production verification fails after promotion

**Result**: Automatic rollback is triggered

**Actions**:
1. Check rollback completed successfully
2. Review error messages in promotion script output
3. Verify staging was working before promotion
4. Check disk space and container logs

### URLs Not Updating

**Problem**: WordPress still shows old URLs after promotion/staging

**Solution**:
```bash
# Manually update URLs
docker compose run --rm wpcli wp search-replace "OLD_URL" "NEW_URL" --all-tables

# Clear WordPress cache if using caching plugin
docker compose run --rm wpcli wp cache flush
```

### Containers Won't Start

**Problem**: Docker containers fail to start

**Solution**:
```bash
# Check Docker service
systemctl status docker

# Check container logs
docker compose logs

# Check port conflicts
netstat -tulpn | grep -E "8081|8181|3324|3424|8824|8924"

# Restart Docker
systemctl restart docker
docker compose up -d
```

### Permission Issues

**Problem**: WordPress can't write files

**Solution**:
```bash
# Fix permissions
docker compose exec wordpress chown -R www-data:www-data /var/www/html
docker compose exec wordpress find /var/www/html -type d -exec chmod 755 {} \;
docker compose exec wordpress find /var/www/html -type f -exec chmod 644 {} \;
```

## Advanced Usage

### Selective Staging

To sync only specific parts (e.g., database only):

```bash
# Export production database
docker exec ${INSTANCE}-db mysqldump -u root -p${MYSQL_ROOT_PASSWORD} ${WORDPRESS_DB_NAME} > /tmp/prod.sql

# Import to staging
docker exec -i ${INSTANCE}-staging-db mysql -u root -p${MYSQL_ROOT_PASSWORD} ${WORDPRESS_DB_NAME} < /tmp/prod.sql

# Update URLs
docker compose run --rm staging-wpcli wp search-replace "${PROD_URL}" "${STAGING_URL}" --all-tables
```

### Multiple Staging Environments

To create additional staging environments, duplicate the staging services in `docker-compose.yml` and add new port configurations in `.env`.

### Custom Backup Location

Modify backup scripts to change backup location:

```bash
# In backup-production.sh, change:
BACKUP_DIR="/path/to/custom/backup/${TIMESTAMP}"
```

## Working with Claude Code

This repository is designed to work seamlessly with Claude Code for AI-assisted development.

### Continuing Conversations

After cloning this repository on a new LXC:

1. **Start Claude Code**:
   ```bash
   claude
   ```

2. **Resume Context**: Claude Code maintains conversation context across sessions. Simply reference previous work or ask Claude to review the setup.

3. **Common Tasks**:
   - "Check the status of the WordPress environments"
   - "Help me troubleshoot why staging creation failed"
   - "Create a custom script to sync only the uploads directory"
   - "Add a new environment variable for X"

### Tips for Claude Code

- All scripts include detailed comments for context
- The `.env.example` file documents all configuration options
- Scripts follow consistent patterns for easy modification
- Error messages are descriptive for troubleshooting

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly in a staging environment
5. Submit a pull request

## License

This project is provided as-is for use in managing WordPress deployments.

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/ecolley/wp-staging/issues
- GitHub Repo: https://github.com/ecolley/wp-staging

## Credits

Built on:
- [WordPress](https://wordpress.org/)
- [Docker](https://www.docker.com/)
- [MySQL](https://www.mysql.com/)
- [phpMyAdmin](https://www.phpmyadmin.net/)
- [WP-CLI](https://wp-cli.org/)

## Changelog

### v1.0.0 (2026-01-10)
- Initial release
- Production and staging environments
- Backup management
- Promotion workflow
- Rollback capability
- LXC setup script
- Comprehensive documentation
