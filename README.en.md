# Universal Frappe/ERPNext Installation Script

This script automatically installs Frappe Framework and ERPNext v15 from scratch on supported Linux distributions in production mode (Nginx + Supervisor).

## Supported OS

- Ubuntu (18.04+)
- Debian (10+)
- RHEL (8+)
- Oracle Linux (8+)
- CentOS/Rocky Linux/AlmaLinux

## What the script installs

1. **System dependencies**: Python 3.10+, Node.js 18+, Yarn, Redis, MariaDB, Nginx, Supervisor, wkhtmltopdf, bmon, mc, htop, vim, nano, screen, rsync, unzip, redis-tools and others
2. **MariaDB**: Configures the DB server with frappe user
3. **Frappe Bench**: Installs the bench tool for managing Frappe
4. **ERPNext v15**: Creates a new site with ERPNext installed
5. **Production setup**: Configures Nginx and Supervisor for production deployment

## Requirements

- Clean system (no pre-installed Frappe)
- Sudo rights (script should not be run as root)
- Internet connection for downloading packages

## Usage

### Basic run (with default settings)

```bash
git clone <this-repo>
cd script-erpnext-install
./install_erpnext.sh
```

**Note:** The script supports language selection (English/Russian) at the beginning of installation.

### With custom parameters

The script uses environment variables for configuration:

```bash
export SITE_NAME="mycompany.local"
export ADMIN_PASSWORD="securepassword123"
export ERP_VERSION="v15"
export FRAPPE_BRANCH="v15"
export INSTALL_PATH="/opt/frappe"
./install_erpnext.sh
```

Available variables:
- `SITE_NAME`: Site name (default: site1.local)
- `ADMIN_PASSWORD`: Administrator password (default: admin)
- `ERP_VERSION`: ERPNext version (default: v15)
- `FRAPPE_BRANCH`: Frappe branch (default: v15)
- `INSTALL_PATH`: Installation path (default: /opt/frappe)
- `INSTALL_MODE`: Installation mode - production or development (default: production)

## Installation process

The script performs the following steps:

1. **OS Detection**: Detects the distribution and configures the package manager
2. **Git Configuration**: Prompts for Git user name and email
3. **Dependency installation**: Installs all necessary packages
4. **MariaDB configuration**: Creates frappe user with frappe_password
5. **Frappe user creation**: Adds system user
6. **Bench installation**: Initializes Frappe Bench
7. **ERPNext installation**: Downloads and installs ERPNext
8. **Service configuration**: Enables Nginx, Supervisor and Redis

## After installation

After successful installation:

1. Add entry to `/etc/hosts`:
   ```
   127.0.0.1 site1.local
   ```

2. Start services:
   ```bash
   sudo supervisorctl start all
   ```

3. Open browser and go to: `http://site1.local`

4. Login with credentials:
   - User: Administrator
   - Password: admin (or your custom)

## Service management

```bash
# Start all services
sudo supervisorctl start all

# Stop all services
sudo supervisorctl stop all

# Restart services
sudo supervisorctl restart all

# View status
sudo supervisorctl status
```

## Logs and troubleshooting

- Installation logs: `/var/log/erpnext_install.log`
- Application logs: `/opt/frappe/frappe-bench/logs/`
- Nginx configuration: `/etc/nginx/sites-available/`

## Security

- Change administrator password after first login
- Configure firewall (ufw/firewalld)
- Consider using HTTPS (Let's Encrypt)
- Regularly update system and applications

## Customization

For more complex settings edit the script:

- Change passwords in MariaDB configuration section
- Add additional apps via bench get-app
- Configure additional sites

## Update

To update ERPNext:

```bash
cd /opt/frappe/frappe-bench
bench update
```

## Support

If problems occur check:
1. Installation logs
2. Service status: `sudo supervisorctl status`
3. Application logs in `/opt/frappe/frappe-bench/logs/`

## Improvements suggestions

### Fixes for specific distributions

**Debian 13 (Bookworm) and newer:**
- wkhtmltopdf: Added snap support and direct .deb download
- Python MySQL: Replaced python3-mysqldb with python3-mysql.connector for compatibility
- MariaDB: Used manual SQL instead of mysql_secure_installation for reliability

**RHEL/OEL 9+:**
- Added AlmaLinux, Rocky Linux support
- Improved EPEL and dependency installation

### Future improvements

1. **Multi-site support**: Ability to install multiple sites in one bench
2. **SSL/HTTPS**: Automatic Let's Encrypt configuration
3. **Backups**: Integration with automatic backups
4. **Monitoring**: Adding Prometheus/Grafana for monitoring
5. **Docker**: Containerization support
6. **CI/CD**: Integration with GitHub Actions for automated testing
7. **Updates**: Automatic updates via cron
8. **Backup**: Built-in backup and restore tools
9. **Security**: Enhanced security (fail2ban, SELinux, AppArmor)
10. **Localization**: Support for different interface languages

### Bug reports

If you find issues:
1. Check logs in `/var/log/erpnext_install.log`
2. Specify OS version and distribution
3. Describe error reproduction steps
4. Attach diagnostic command output

## License

This script is provided as is, without warranties.
