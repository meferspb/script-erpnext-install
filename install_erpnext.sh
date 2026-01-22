#!/bin/bash

# Universal Frappe/ERPNext Installation Script v1.0
# Универсальный скрипт установки Frappe/ERPNext v1.0
# Supports Ubuntu/Debian/RHEL/OEL distributions
# Поддерживает дистрибутивы Ubuntu/Debian/RHEL/OEL
# Production setup with Nginx + Supervisor, ERPNext v15
# Производственная настройка с Nginx + Supervisor, ERPNext v15

set -e  # Exit on any error

# Colors for output
# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration (can be overridden with environment variables)
# Конфигурация по умолчанию (может быть переопределена переменными окружения)
DEFAULT_SITE_NAME="${SITE_NAME:-site1.local}"
DEFAULT_ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
DEFAULT_ERP_VERSION="${ERP_VERSION:-v15}"
DEFAULT_FRAPPE_BRANCH="${FRAPPE_BRANCH:-v15}"
INSTALL_PATH="${INSTALL_PATH:-}"
INSTALL_MODE="${INSTALL_MODE:-production}"  # production or development
# Default log file — place in user's home by default to avoid permission errors
LOG_FILE="${LOG_FILE:-$HOME/erpnext_install.log}"
# Database passwords (generated if not provided)
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)}"
DB_PASSWORD="${DB_PASSWORD:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)}"
GIT_USER_NAME=""
GIT_USER_EMAIL=""
LANG="en"  # Default language: en or ru

# Function to log messages
# Функция для логирования сообщений
log() {
    local msg="$1"
    # Print colored output to stdout
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $msg${NC}"
    # Append plain message to logfile; ignore failures to avoid exiting (set -e)
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    local msg="$1"
    echo -e "${RED}[ERROR] $msg${NC}"
    echo "[ERROR] $msg" >> "$LOG_FILE" 2>/dev/null || true
    exit 1
}

success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS] $msg${NC}"
    echo "[SUCCESS] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING] $msg${NC}"
    echo "[WARNING] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Install wkhtmltopdf
# Установить wkhtmltopdf
install_wkhtmltopdf() {
    if [[ "$LANG" == "ru" ]]; then
        log "Установка wkhtmltopdf..."
        already_msg="wkhtmltopdf уже установлен"
    else
        log "Installing wkhtmltopdf..."
        already_msg="wkhtmltopdf already installed"
    fi

    if command -v wkhtmltopdf &> /dev/null; then
        log "$already_msg"
        return
    fi

    case $OS_FAMILY in
        debian)
            # Try snap first (works on most Debian versions)
            if command -v snap &> /dev/null; then
                sudo snap install wkhtmltopdf
            else
                # Fallback: download from GitHub releases
                wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
                sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || true
                sudo apt install -f -y
                rm wkhtmltox_0.12.6.1-2.jammy_amd64.deb
            fi
            ;;
        rhel)
            # Use rpm from wkhtmltopdf site
            wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox-0.12.6.1-2.centos8.x86_64.rpm
            sudo rpm -i wkhtmltox-0.12.6.1-2.centos8.x86_64.rpm || true
            rm wkhtmltox-0.12.6.1-2.centos8.x86_64.rpm
            ;;
    esac

    if ! command -v wkhtmltopdf &> /dev/null; then
        if [[ "$LANG" == "ru" ]]; then
            warning "Установка wkhtmltopdf не удалась, продолжаем без неё"
        else
            warning "wkhtmltopdf installation failed, continuing without it"
        fi
    fi
}

# Verify versions
# Проверить версии
verify_versions() {
    if [[ "$LANG" == "ru" ]]; then
        log "Проверка установленных версий..."
        python_err="Требуется Python 3.10+"
        node_err="Требуется Node.js 22+"
    else
        log "Verifying installed versions..."
        python_err="Python 3.10+ required"
        node_err="Node.js 22+ required"
    fi

    # Python version check
    if ! command -v python3 >/dev/null 2>&1; then
        error "$python_err: python3 not found"
    fi
    python_version=$(python3 -c 'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))' 2>/dev/null || true)
    if ! python3 - <<'PY'
import sys
v=sys.version_info
sys.exit(0 if (v.major>3 or (v.major==3 and v.minor>=10)) else 1)
PY
    then
        error "$python_err: $python_version"
    fi
    log "Python version: $python_version ✓"

    # Node.js version check
    if ! command -v node >/dev/null 2>&1; then
        error "$node_err: node not found"
    fi
    node_version=$(node -v 2>/dev/null | sed 's/^v//')
    if ! node -e 'const v=process.versions.node.split("."); if(+v[0]>22 || (+v[0]==22 && +v[1]>=0)) process.exit(0); else process.exit(1);' 2>/dev/null; then
        error "$node_err: $node_version"
    fi
    log "Node.js version: $node_version ✓"

    # MariaDB version check (if installed)
    if command -v mariadb >/dev/null 2>&1; then
        mariadb_version=$(mariadb --version 2>/dev/null | sed -n 's/.*\([0-9]\+\.[0-9]\+\).*/\1/p' || true)
        log "MariaDB version: $mariadb_version ✓"
    fi
}

# Helper to execute MySQL/MariaDB SQL safely
# Tries: 1) sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "SQL"  2) sudo mysql -e "SQL"  3) sudo mysql --defaults-file=/etc/mysql/debian.cnf -e "SQL"
run_mysql() {
    local sql="$1"
    if [[ -n "$DB_ROOT_PASSWORD" ]]; then
        if sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "$sql" >/dev/null 2>&1; then
            return 0
        fi
    fi
    if sudo mysql -e "$sql" >/dev/null 2>&1; then
        return 0
    fi
    if [[ -f /etc/mysql/debian.cnf ]]; then
        if sudo mysql --defaults-file=/etc/mysql/debian.cnf -e "$sql" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Detect OS and set package manager
# Определить ОС и установить менеджер пакетов
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                OS_FAMILY="debian"
                PKG_MANAGER="apt"
                UPDATE_CMD="apt update"
                INSTALL_CMD="apt install -y"
                REMOVE_CMD="apt remove -y"
                PURGE_CMD="apt-get purge -y"
                ;;
            rhel|centos|ol|rocky|almalinux)
                OS_FAMILY="rhel"
                if command -v dnf &> /dev/null; then
                    PKG_MANAGER="dnf"
                    UPDATE_CMD="dnf update -y"
                    INSTALL_CMD="dnf install -y"
                    REMOVE_CMD="dnf remove -y"
                    PURGE_CMD="dnf remove -y"
                else
                    PKG_MANAGER="yum"
                    UPDATE_CMD="yum update -y"
                    INSTALL_CMD="yum install -y"
                    REMOVE_CMD="yum remove -y"
                    PURGE_CMD="yum remove -y"
                fi
                ;;
            *)
                if [[ "$LANG" == "ru" ]]; then
                    error "Неподдерживаемая ОС: $ID. Этот скрипт поддерживает производные Ubuntu/Debian/RHEL/OEL."
                else
                    error "Unsupported OS: $ID. This script supports Ubuntu/Debian/RHEL/OEL derivatives."
                fi
                ;;
        esac
        if [[ "$LANG" == "ru" ]]; then
            log "Обнаружена ОС: $PRETTY_NAME (Семейство: $OS_FAMILY, Менеджер пакетов: $PKG_MANAGER)"
        else
            log "Detected OS: $PRETTY_NAME (Family: $OS_FAMILY, Package Manager: $PKG_MANAGER)"
        fi
    else
        if [[ "$LANG" == "ru" ]]; then
            error "Не удалось определить ОС. Файл /etc/os-release не найден."
        else
            error "Cannot detect OS. /etc/os-release not found."
        fi
    fi
}

# Check if running as root
# Проверить, запущен ли скрипт от root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        if [[ "$LANG" == "ru" ]]; then
            error "Этот скрипт не должен запускаться от root. Он обрабатывает повышение прав sudo внутренне."
        else
            error "This script should not be run as root. It will handle sudo elevation internally."
        fi
    fi
}

# Check for existing installation
# Проверить существующую установку
check_existing_installation() {
    if [[ -d "$INSTALL_PATH/frappe-bench" ]]; then
        if [[ "$LANG" == "ru" ]]; then
            warning "Найдена существующая установка Frappe Bench в $INSTALL_PATH/frappe-bench"
            read -p "Хотите продолжить и возможно перезаписать? (y/N): " -n 1 -r
            echo
            abort_msg="Установка прервана пользователем."
        else
            warning "Existing Frappe Bench installation found at $INSTALL_PATH/frappe-bench"
            read -p "Do you want to continue and potentially overwrite? (y/N): " -n 1 -r
            echo
            abort_msg="Installation aborted by user."
        fi
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "$abort_msg"
            exit 0
        fi
    fi
}

# Install system dependencies
# Установить системные зависимости
install_system_deps() {
    if [[ "$LANG" == "ru" ]]; then
        log "Установка системных зависимостей..."
        success_msg="Системные зависимости установлены"
    else
        log "Installing system dependencies..."
        success_msg="System dependencies installed"
    fi

    # Common packages
    local common_packages="git curl wget python3 python3-pip python3-dev python3-setuptools python3-venv redis-server mariadb-server nginx supervisor build-essential libssl-dev libffi-dev bc bmon mc htop vim nano screen rsync unzip"

    # OS-specific packages — handle missing packages on newer distributions
    # Run update first so package availability info is fresh
    sudo $UPDATE_CMD

    # Ensure locales are present to avoid perl/apt-listchanges locale warnings
    if [[ "$OS_FAMILY" == "debian" ]]; then
        if [[ "$LANG" == "ru" ]]; then
            if ! locale -a | grep -qi ru_RU; then
                sudo $INSTALL_CMD locales || true
                sudo sed -i 's/^# *ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen || true
                sudo locale-gen || true
                sudo update-locale LANG=ru_RU.UTF-8 || true
            fi
        else
            if ! locale -a | grep -qi en_US; then
                sudo $INSTALL_CMD locales || true
                sudo sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
                sudo locale-gen || true
                sudo update-locale LANG=en_US.UTF-8 || true
            fi
        fi
    fi

    case $OS_FAMILY in
        debian)
            # Ubuntu/Debian specific; check candidate availability and substitute if missing
            local os_packages_base=(software-properties-common python3-distutils libmysqlclient-dev)
            local os_packages_arr=()
            for pkg in "${os_packages_base[@]}"; do
                candidate=$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}') || candidate=""
                if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
                    os_packages_arr+=("$pkg")
                    continue
                fi

                case $pkg in
                    libmysqlclient-dev)
                        # prefer default-libmysqlclient-dev, otherwise libmariadb dev packages
                        candidate=$(apt-cache policy default-libmysqlclient-dev 2>/dev/null | awk '/Candidate:/ {print $2}') || candidate=""
                        if [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
                            os_packages_arr+=("default-libmysqlclient-dev")
                        else
                            os_packages_arr+=("libmariadb-dev-compat" "libmariadb-dev")
                        fi
                        ;;
                    python3-distutils)
                        # Try to find a versioned distutils package (e.g., python3.11-distutils)
                        alt_pkg=$(apt-cache search --names-only '^python3[0-9\.]*-distutils$' 2>/dev/null | awk '{print $1; exit}') || alt_pkg=""
                        if [[ -n "$alt_pkg" ]]; then
                            os_packages_arr+=("$alt_pkg")
                        else
                            warning "Package python3-distutils not found; adding python3-venv and python3-setuptools as fallback"
                            os_packages_arr+=("python3-venv" "python3-setuptools")
                        fi
                        ;;
                    software-properties-common)
                        warning "Package software-properties-common not found; skipping add-apt-repository support"
                        ;;
                    *)
                        warning "Package $pkg not found; skipping"
                        ;;
                esac
            done
            # Join array into a space-separated string for apt
            local os_packages="${os_packages_arr[*]}"
            ;;
        rhel)
            # RHEL/OEL specific
            local os_packages="epel-release python3-devel mysql-devel gcc-c++"
            # Enable EPEL if not already
            if ! rpm -q epel-release &> /dev/null; then
                $INSTALL_CMD epel-release
            fi
            ;;
    esac

    # Install all packages
    sudo $INSTALL_CMD $common_packages $os_packages

    # Install Node.js 22+ and Yarn
    case $OS_FAMILY in
        debian)
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
            sudo $INSTALL_CMD nodejs
            # Add Yarn GPG key without using deprecated apt-key
            if ! command -v gpg >/dev/null 2>&1; then
                sudo $INSTALL_CMD gnupg dirmngr || true
            fi
            curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/yarn-archive-keyring.gpg || true
            echo "deb [signed-by=/usr/share/keyrings/yarn-archive-keyring.gpg] https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
            sudo $INSTALL_CMD yarn || true
            ;;
        rhel)
            curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo -E bash -
            sudo $INSTALL_CMD nodejs
            curl --silent --location https://dl.yarnpkg.com/rpm/yarn.repo | sudo tee /etc/yum.repos.d/yarn.repo
            sudo $INSTALL_CMD yarn
            ;;
    esac

    # Install wkhtmltopdf
    install_wkhtmltopdf

    # Verify versions
    verify_versions

    success "$success_msg"
}

# Configure security: install and enable fail2ban and ensure firewall keeps ports 22,80,443 open
# Настройка безопасности: fail2ban и брандмауэр — порты 22,80,443 всегда открыты
configure_security() {
    if [[ "$LANG" == "ru" ]]; then
        log "Настройка безопасности: fail2ban и брандмауэр..."
        success_msg="Fail2ban и брандмауэр настроены"
    else
        log "Configuring security: fail2ban and firewall..."
        success_msg="Fail2ban and firewall configured"
    fi

    case $OS_FAMILY in
        debian)
            sudo $INSTALL_CMD fail2ban ufw || true

            # fail2ban basic local configuration (idempotent)
            sudo mkdir -p /etc/fail2ban/jail.d
            sudo tee /etc/fail2ban/jail.d/erpnext.local > /dev/null <<'EOF'
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
EOF

            sudo systemctl enable --now fail2ban || true

            # Ensure UFW is present and allow required ports (idempotent)
            if command -v ufw >/dev/null 2>&1; then
                sudo ufw allow 22/tcp
                sudo ufw allow 80/tcp
                sudo ufw allow 443/tcp
                sudo ufw default deny incoming
                sudo ufw default allow outgoing
                sudo ufw --force enable
            fi
            ;;
        rhel)
            sudo $INSTALL_CMD fail2ban firewalld || true
            sudo systemctl enable --now fail2ban || true
            sudo systemctl enable --now firewalld || true
            sudo firewall-cmd --permanent --add-service=ssh || true
            sudo firewall-cmd --permanent --add-service=http || true
            sudo firewall-cmd --permanent --add-service=https || true
            sudo firewall-cmd --reload || true
            ;;
    esac

    success "$success_msg"
}

# Configure MariaDB
# Настроить MariaDB
configure_mariadb() {
    if [[ "$LANG" == "ru" ]]; then
        log "Настройка MariaDB..."
        success_msg="MariaDB настроена"
    else
        log "Configuring MariaDB..."
        success_msg="MariaDB configured"
    fi

    # If MariaDB/MySQL already installed, purge it (packages + data) to ensure clean reinstall
    if command -v mysql >/dev/null 2>&1 || systemctl list-units --type=service | grep -Eq 'mariadb|mysql'; then
        if [[ "$LANG" == "ru" ]]; then
            log "Найдена существующая установка MariaDB/MySQL — удаляю (purge) и очищаю данные..."
        else
            log "Existing MariaDB/MySQL detected — purging and removing data..."
        fi

        case $OS_FAMILY in
            debian)
                sudo systemctl stop mariadb || sudo systemctl stop mysql || true
                # Use purge command variable to properly purge packages if present
                sudo $PURGE_CMD mariadb-server mariadb-client mariadb-common mariadb-server-core-* mariadb-client-core-* 2>/dev/null || true
                # Try to purge mysql packages only if present in apt cache
                if apt-cache policy mysql-server >/dev/null 2>&1; then
                    sudo $PURGE_CMD mysql-server mysql-client mysql-common 2>/dev/null || true
                fi
                sudo apt autoremove -y || true
                ;;
            rhel)
                sudo systemctl stop mariadb || sudo systemctl stop mysql || true
                sudo $REMOVE_CMD mariadb-server mariadb mariadb-client mysql-server mysql 2>/dev/null || true
                ;;
        esac

        sudo rm -rf /var/lib/mysql /etc/mysql /var/log/mysql /var/log/mysql.* /var/run/mysqld 2>/dev/null || true
        sudo deluser --remove-home mysql 2>/dev/null || true
        sudo groupdel mysql 2>/dev/null || true

        if [[ "$LANG" == "ru" ]]; then
            log "Старая установка MariaDB удалена. Продолжаю чистую установку."
        else
            log "Old MariaDB installation removed. Proceeding with fresh install."
        fi
    fi

    # Install MariaDB server fresh
    sudo $INSTALL_CMD mariadb-server || true

    # Start and enable MariaDB
    sudo systemctl start mariadb || sudo systemctl start mysql || true
    sudo systemctl enable mariadb || sudo systemctl enable mysql || true

    # Wait for MariaDB to start and verify
    sleep 5
    if ! sudo systemctl is-active --quiet mariadb && ! sudo systemctl is-active --quiet mysql; then
        warning "MariaDB service failed to start. Collecting recent journal logs to /tmp/mariadb_journal.log"
        sudo journalctl -xeu mariadb.service -n 200 > /tmp/mariadb_journal.log 2>/dev/null || true
        if [[ "$LANG" == "ru" ]]; then
            error "Сервис MariaDB не запущен. Проверьте /tmp/mariadb_journal.log или выполните 'sudo systemctl status mariadb.service' для подробностей."
        else
            error "MariaDB service is not running. Check /tmp/mariadb_journal.log or run 'sudo systemctl status mariadb.service' for details."
        fi
    fi

    # Secure MariaDB installation manually (try multiple auth methods)
    if run_mysql "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}'; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test_%'; FLUSH PRIVILEGES;"; then
        log "MariaDB: root user configured"
    else
        warning "Could not run SQL as root without password. You may need to set root password manually or check MariaDB auth settings."
    fi

    # Create frappe database user
    if run_mysql "CREATE USER IF NOT EXISTS 'frappe'@'localhost' IDENTIFIED BY '${DB_PASSWORD}'; GRANT ALL PRIVILEGES ON *.* TO 'frappe'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;"; then
        log "MariaDB: frappe user ensured"
    else
        error "Failed to create 'frappe' database user. Please verify MariaDB root access."
    fi

    success "$success_msg"
}

# Create frappe user
# Создать пользователя frappe
create_frappe_user() {
    if [[ "$LANG" == "ru" ]]; then
        log "Создание пользователя frappe..."
        success_msg="Пользователь frappe создан"
    else
        log "Creating frappe user..."
        success_msg="Frappe user created"
    fi

    if ! id -u frappe &> /dev/null; then
        sudo useradd -m -s /bin/bash frappe
    fi

    # Add frappe to sudo or wheel group so bench can use sudo when needed
    if getent group sudo >/dev/null 2>&1; then
        sudo usermod -aG sudo frappe
    else
        sudo usermod -aG wheel frappe
    fi

    # Set up directories (quote paths)
    sudo mkdir -p "$INSTALL_PATH"
    sudo chown -R frappe:frappe "$INSTALL_PATH"

    # Configure Git for frappe user
    sudo -u frappe bash -c "cd /home/frappe && git config --global user.name '$GIT_USER_NAME' && git config --global user.email '$GIT_USER_EMAIL'"

    success "$success_msg"
}

# Install bench
# Установить bench
install_bench() {
    if [[ "$LANG" == "ru" ]]; then
        log "Установка Frappe Bench..."
        success_msg="Bench установлен"
    else
        log "Installing Frappe Bench..."
        success_msg="Bench installed"
    fi

    # Install bench package system-wide, then initialise bench as the frappe user
    sudo pip3 install --break-system-packages --ignore-installed frappe-bench
    sudo -u frappe bash -c "cd '$INSTALL_PATH' && bench init --frappe-branch '$DEFAULT_FRAPPE_BRANCH' frappe-bench && cd frappe-bench && bench setup production frappe"

    success "$success_msg"
}

# Install ERPNext
# Установить ERPNext
install_erpnext() {
    if [[ "$LANG" == "ru" ]]; then
        log "Установка ERPNext $DEFAULT_ERP_VERSION..."
        success_msg="ERPNext установлен"
    else
        log "Installing ERPNext $DEFAULT_ERP_VERSION..."
        success_msg="ERPNext installed"
    fi

    sudo -u frappe bash -c "cd '$INSTALL_PATH/frappe-bench' && \
        bench get-app erpnext --branch '$DEFAULT_ERP_VERSION' && \
        bench new-site '$DEFAULT_SITE_NAME' --admin-password '$DEFAULT_ADMIN_PASSWORD' --db-password '${DB_PASSWORD}' && \
        bench --site '$DEFAULT_SITE_NAME' install-app erpnext && \
        bench setup production frappe"

    success "$success_msg"
}

# Configure Nginx and Supervisor
# Настроить Nginx и Supervisor
configure_services() {
    if [[ "$LANG" == "ru" ]]; then
        log "Настройка Nginx и Supervisor..."
        success_msg="Сервисы настроены"
    else
        log "Configuring Nginx and Supervisor..."
        success_msg="Services configured"
    fi

    # Enable and start services
    sudo systemctl enable nginx
    sudo systemctl enable supervisor
    sudo systemctl enable redis-server

    # Reload services
    sudo systemctl reload nginx
    sudo supervisorctl reread
    sudo supervisorctl update

    success "$success_msg"
}

# Final setup
# Финальная настройка
final_setup() {
    if [[ "$LANG" == "ru" ]]; then
        log "Выполнение финальной настройки..."
        success_msg="Установка завершена успешно!"
        details_msg="Смотрите файл erpnext_install_summary.txt для подробностей"
    else
        log "Performing final setup..."
        success_msg="Installation completed successfully!"
        details_msg="See erpnext_install_summary.txt for details"
    fi

    # Set proper permissions
    sudo chown -R frappe:frappe "$INSTALL_PATH"

    # Create a summary
    cat << EOF > erpnext_install_summary.txt
ERPNext Installation Summary
===========================

Site URL: http://$DEFAULT_SITE_NAME
Admin User: Administrator
Admin Password: $DEFAULT_ADMIN_PASSWORD
Database Password: $DB_PASSWORD

Installation Path: $INSTALL_PATH/frappe-bench

To start services:
sudo supervisorctl start all

To stop services:
sudo supervisorctl stop all

To access the site, add this to /etc/hosts:
127.0.0.1 $DEFAULT_SITE_NAME

Then visit: http://$DEFAULT_SITE_NAME
EOF

    success "$success_msg"
    log "$details_msg"
}

# Select language
# Выбрать язык
select_language() {
    echo "Select language / Выберите язык:"
    echo "1. English"
    echo "2. Русский"
    read -p "Enter choice (1 or 2, default: 1): " lang_choice
    case $lang_choice in
        2)
            LANG="ru"
            ;;
        *)
            LANG="en"
            ;;
    esac
}

# Configure Git settings
# Настроить параметры Git
configure_git() {
    if [[ "$LANG" == "ru" ]]; then
        log "Настройка параметров Git..."
        read -p "Введите имя пользователя Git: " GIT_USER_NAME
        read -p "Введите email пользователя Git: " GIT_USER_EMAIL
        log_msg="Git настроен для пользователя: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    else
        log "Configuring Git settings..."
        read -p "Enter Git user name: " GIT_USER_NAME
        read -p "Enter Git user email: " GIT_USER_EMAIL
        log_msg="Git configured with user: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    fi

    # Configure Git globally for the current user
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"

    log "$log_msg"
}

# Main function
# Главная функция
main() {
    # Select language
    select_language

    if [[ "$LANG" == "ru" ]]; then
        log "Запуск установки ERPNext..."
        start_msg="Установка ERPNext завершена. Проверьте файл erpnext_install_summary.txt для следующих шагов."
    else
        log "Starting ERPNext installation..."
        start_msg="ERPNext installation completed. Please check the summary file for next steps."
    fi

    check_root

    # Select installation path if not set via environment variable
    if [[ -z "$INSTALL_PATH" ]]; then
        if [[ "$LANG" == "ru" ]]; then
            read -p "Введите путь установки (по умолчанию: /opt/frappe): " user_path
        else
            read -p "Enter installation path (default: /opt/frappe): " user_path
        fi
        INSTALL_PATH="${user_path:-/opt/frappe}"
    fi

    # Check if installation path is under /home and warn about permission issues
    if [[ "$INSTALL_PATH" == /home/* ]]; then
        if [[ "$LANG" == "ru" ]]; then
            warning "Путь установки находится в /home. Это может вызвать проблемы с разрешениями для пользователя frappe. Рекомендуется использовать /opt/frappe."
        else
            warning "Installation path is under /home. This may cause permission issues for the frappe user. It is recommended to use /opt/frappe."
        fi
    fi

    # Configure Git settings
    configure_git

    # Prompt for MariaDB root password with confirmation (allow user to override generated one)
    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        DB_ROOT_PASSWORD=""
    fi

    attempts=0
    while true; do
        if [[ "$LANG" == "ru" ]]; then
            read -s -p "Введите пароль для пользователя root MariaDB (оставьте пустым для автогенерации): " input_db_root_pwd
        else
            read -s -p "Enter MariaDB root password (leave empty to generate): " input_db_root_pwd
        fi
        echo

        # If user left blank, keep generated/default
        if [[ -z "$input_db_root_pwd" ]]; then
            break
        fi

        if [[ "$LANG" == "ru" ]]; then
            read -s -p "Подтвердите пароль: " input_db_root_pwd_confirm
        else
            read -s -p "Confirm password: " input_db_root_pwd_confirm
        fi
        echo

        if [[ "$input_db_root_pwd" == "$input_db_root_pwd_confirm" ]]; then
            DB_ROOT_PASSWORD="$input_db_root_pwd"
            break
        else
            attempts=$((attempts+1))
            if [[ "$LANG" == "ru" ]]; then
                warning "Пароли не совпадают. Попробуйте снова."
            else
                warning "Passwords do not match. Try again."
            fi
            if [[ $attempts -ge 3 ]]; then
                if [[ "$LANG" == "ru" ]]; then
                    warning "Превышено число попыток подтверждения пароля. Используется автогенерированный пароль."
                else
                    warning "Password confirmation attempts exceeded. Using generated password."
                fi
                # Ensure DB_ROOT_PASSWORD has a value
                DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)}"
                break
            fi
        fi
    done

    check_existing_installation
    detect_os
    install_system_deps
    configure_security
    configure_mariadb
    create_frappe_user
    install_bench
    install_erpnext
    configure_services
    final_setup

    log "$start_msg"
}

# Run main function
main "$@"
