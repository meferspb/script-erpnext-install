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
DEFAULT_ERP_VERSION="${ERP_VERSION:-version-15}"
DEFAULT_FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-15}"
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

# Enhanced logging functions with detailed information
# Расширенные функции логирования с подробной информацией

# Global variables for timing and progress tracking
SCRIPT_START_TIME=""
FUNCTION_START_TIME=""
CURRENT_STEP=""
TOTAL_STEPS=10
COMPLETED_STEPS=0

log_system_info() {
    log "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ==="
    log "Дата и время: $(date)"
    log "Пользователь: $(whoami)"
    log "UID: $(id -u)"
    log "Рабочая директория: $(pwd)"
    log "ОС: $(uname -a)"
    log "Shell: $SHELL"
    log "PATH: $PATH"
    log "Переменные окружения:"
    env | grep -E "(LANG|LC_|DEBIAN_FRONTEND|HOME|USER|PWD)" | while read line; do log "  $line"; done
    log "=== КОНЕЦ СИСТЕМНОЙ ИНФОРМАЦИИ ==="
}

log_function_enter() {
    local func_name="$1"
    FUNCTION_START_TIME=$(date +%s)
    log ">>> ВХОД В ФУНКЦИЮ: $func_name"
    log "Время начала: $(date '+%Y-%m-%d %H:%M:%S')"
}

log_function_exit() {
    local func_name="$1"
    local exit_code="${2:-0}"
    local end_time=$(date +%s)
    local duration=$((end_time - FUNCTION_START_TIME))
    log "<<< ВЫХОД ИЗ ФУНКЦИИ: $func_name"
    log "Время выполнения: ${duration} сек"
    log "Код выхода: $exit_code"
    if [[ $exit_code -eq 0 ]]; then
        ((COMPLETED_STEPS++))
        log "Прогресс: $COMPLETED_STEPS/$TOTAL_STEPS шагов завершено"
    fi
}

log_command_start() {
    local cmd="$1"
    log ">>> ИСПОЛНЕНИЕ КОМАНДЫ: $cmd"
}

log_command_end() {
    local cmd="$1"
    local exit_code="$2"
    log "<<< КОМАНДА ЗАВЕРШЕНА: $cmd"
    log "Код выхода команды: $exit_code"
}

log_step_start() {
    local step_name="$1"
    CURRENT_STEP="$step_name"
    log "=== НАЧАЛО ШАГА: $step_name ==="
    log "Общее время работы: $(( $(date +%s) - SCRIPT_START_TIME )) сек"
}

log_step_end() {
    local step_name="$1"
    log "=== ШАГ ЗАВЕРШЕН: $step_name ==="
}

log_debug() {
    local msg="$1"
    echo -e "${BLUE}[DEBUG] $msg${NC}"
    echo "[DEBUG] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

log() {
    local msg="$1"
    # Print colored output to stdout
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $msg${NC}"
    # Append plain message to logfile; ignore failures to avoid exiting (set -e)
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    local msg="$1"
    local line_info="${BASH_LINENO[0]}"
    local func_info="${FUNCNAME[1]}"
    echo -e "${RED}[ERROR] $msg${NC}"
    echo "[ERROR] $msg (функция: $func_info, строка: $line_info)" >> "$LOG_FILE" 2>/dev/null || true
    log "=== АВАРИЙНОЕ ЗАВЕРШЕНИЕ СКРИПТА ==="
    log "Последний шаг: $CURRENT_STEP"
    log "Выполненные шаги: $COMPLETED_STEPS/$TOTAL_STEPS"
    log "Общее время работы: $(( $(date +%s) - SCRIPT_START_TIME )) сек"
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
    log_function_enter "install_wkhtmltopdf"

    if [[ "$LANG" == "ru" ]]; then
        log "Установка wkhtmltopdf..."
        already_msg="wkhtmltopdf уже установлен"
    else
        log "Installing wkhtmltopdf..."
        already_msg="wkhtmltopdf already installed"
    fi

    if command -v wkhtmltopdf &> /dev/null; then
        log "$already_msg"
        log_function_exit "install_wkhtmltopdf" 0
        return
    fi

    case $OS_FAMILY in
        debian)
            # Try to install from Debian backports first
            if apt-cache policy wkhtmltopdf 2>/dev/null | grep -q "Candidate:"; then
                sudo $INSTALL_CMD wkhtmltopdf || true
            fi

            # If not available in repos, try snap
            if ! command -v wkhtmltopdf &> /dev/null && command -v snap &> /dev/null; then
                sudo snap install wkhtmltopdf || true
            fi

            # Last resort: manual installation with cleanup
            if ! command -v wkhtmltopdf &> /dev/null; then
                wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
                sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || true
                sudo apt install -f -y || true
                rm -f wkhtmltox_0.12.6.1-2.jammy_amd64.deb

                # Mark as auto-installed to prevent apt issues
                if command -v wkhtmltopdf &> /dev/null; then
                    echo "wkhtmltox install ok installed" | sudo dpkg --set-selections || true
                fi
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

    log_function_exit "install_wkhtmltopdf" 0
}

# Verify versions
# Проверить версии
verify_versions() {
    log_function_enter "verify_versions"
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

    log_function_exit "verify_versions" 0
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
    local common_packages="git curl wget python3 python3-pip python3-dev python3-setuptools python3-venv redis-server mariadb-server nginx supervisor cron build-essential libssl-dev libffi-dev bc bmon mc htop vim nano screen rsync unzip"

    # OS-specific packages — handle missing packages on newer distributions
    # Ensure Debian repositories are properly configured
    if [[ "$OS_FAMILY" == "debian" ]]; then
        # Check and enable required Debian repositories
        local sources_file="/etc/apt/sources.list"
        if [[ -f "$sources_file" ]]; then
            # Check if main, contrib, non-free, non-free-firmware are enabled
            local has_main=$(grep -q "deb.*main" "$sources_file" && echo "yes" || echo "no")
            local has_contrib=$(grep -q "deb.*contrib" "$sources_file" && echo "yes" || echo "no")
            local has_nonfree=$(grep -q "deb.*non-free[^-]" "$sources_file" && echo "yes" || echo "no")
            local has_nonfree_firmware=$(grep -q "deb.*non-free-firmware" "$sources_file" && echo "yes" || echo "no")

            if [[ "$has_main" == "no" || "$has_contrib" == "no" || "$has_nonfree" == "no" || "$has_nonfree_firmware" == "no" ]]; then
                log "Enabling required Debian repositories (main, contrib, non-free, non-free-firmware)..."
                # Backup original sources.list
                sudo cp "$sources_file" "${sources_file}.backup"

                # Enable required components in existing deb lines
                sudo sed -i 's/deb http/deb http/g; s/deb http/deb http/g' "$sources_file"
                sudo sed -i 's/deb http\([^ ]*\) \([^ ]*\) \([^ ]*\)$/deb http\1 \2 \3 main contrib non-free non-free-firmware/g' "$sources_file"

                log "Debian repositories updated. Updating package cache..."
            fi
        fi
    fi

    # Run update first so package availability info is fresh
    sudo $UPDATE_CMD

    # Fix any interrupted dpkg operations first
    if [[ "$OS_FAMILY" == "debian" ]]; then
        if sudo dpkg --configure -a --status-fd 1 2>/dev/null | grep -q "half-configured\|unpacked\|half-installed"; then
            log "Fixing interrupted dpkg operations..."
            sudo dpkg --configure -a || true
        fi

        # Clean up any problematic wkhtmltox installations
        if dpkg -l | grep -q "^[a-zA-Z].*wkhtmltox"; then
            log "Removing conflicting wkhtmltox package..."
            sudo dpkg --purge --force-depends wkhtmltox || true
            sudo apt autoremove -y || true
        fi
    fi

    # Install and configure locales properly
    if [[ "$OS_FAMILY" == "debian" ]]; then
        sudo $INSTALL_CMD locales || true

        # Generate required locales
        local locales=("ru_RU.UTF-8 UTF-8" "en_US.UTF-8 UTF-8" "uz_UZ.UTF-8 UTF-8")

        for locale_line in "${locales[@]}"; do
            locale_name=$(echo "$locale_line" | cut -d' ' -f1)
            if ! locale -a | grep -qi "^${locale_name%%.*}"; then
                sudo sed -i "s/^# *${locale_line}/${locale_line}/" /etc/locale.gen || true
            fi
        done

        sudo locale-gen || true

        # Set all locale variables properly
        if [[ "$LANG" == "ru" ]]; then
            sudo update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 LC_CTYPE=ru_RU.UTF-8 LC_MESSAGES=ru_RU.UTF-8 || true
        else
            sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 LC_MESSAGES=en_US.UTF-8 || true
        fi

        # Export locale variables for current session
        if [[ "$LANG" == "ru" ]]; then
            export LANG=ru_RU.UTF-8
            export LC_ALL=ru_RU.UTF-8
            export LC_CTYPE=ru_RU.UTF-8
            export LC_MESSAGES=ru_RU.UTF-8
        else
            export LANG=en_US.UTF-8
            export LC_ALL=en_US.UTF-8
            export LC_CTYPE=en_US.UTF-8
            export LC_MESSAGES=en_US.UTF-8
        fi
    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        # For RHEL systems, locales are usually available by default
        # but we can ensure UTF-8 support
        if command -v localedef &> /dev/null; then
            sudo localedef -c -i ru_RU -f UTF-8 ru_RU.UTF-8 || true
            sudo localedef -c -i en_US -f UTF-8 en_US.UTF-8 || true
            sudo localedef -c -i uz_UZ -f UTF-8 uz_UZ.UTF-8 || true
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

            # Check if yarn keyring already exists and matches expected
            local yarn_keyring="/usr/share/keyrings/yarn-archive-keyring.gpg"
            local expected_keyring_content
            expected_keyring_content=$(curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor 2>/dev/null || true)

            if [[ -f "$yarn_keyring" ]]; then
                local current_keyring_content
                current_keyring_content=$(gpg --dearmor < "$yarn_keyring" 2>/dev/null || true)

                if [[ "$current_keyring_content" == "$expected_keyring_content" ]]; then
                    log "Yarn GPG keyring already exists and matches expected - skipping download"
                else
                    log "Yarn GPG keyring exists but differs - updating"
                    echo "$expected_keyring_content" | sudo tee "$yarn_keyring" >/dev/null
                fi
            else
                log "Downloading Yarn GPG keyring"
                echo "$expected_keyring_content" | sudo tee "$yarn_keyring" >/dev/null
            fi

            echo "deb [signed-by=$yarn_keyring] https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
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

    # Create frappe group if it doesn't exist and add frappe user to it
    if ! getent group frappe >/dev/null 2>&1; then
        sudo groupadd frappe || true
    fi

    # Add frappe to sudo or wheel group so bench can use sudo when needed
    if getent group sudo >/dev/null 2>&1; then
        sudo usermod -aG sudo frappe
        sudo usermod -aG frappe frappe
        # Allow passwordless sudo for frappe user
        echo 'frappe ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/frappe >/dev/null
    else
        sudo usermod -aG wheel frappe
        sudo usermod -aG frappe frappe
        # For RHEL, allow passwordless sudo
        echo 'frappe ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/frappe >/dev/null
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
    if command -v uv >/dev/null 2>&1; then
        sudo uv pip install --system --break-system-packages frappe-bench
    else
        sudo pip3 install --break-system-packages --ignore-installed frappe-bench
    fi
    sudo -u frappe bash -c "cd '$INSTALL_PATH' && rm -rf frappe-bench && bench init --frappe-branch '$DEFAULT_FRAPPE_BRANCH' frappe-bench && cd frappe-bench && bench setup production frappe"

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
        bench --site '$DEFAULT_SITE_NAME' install-app erpnext"

    # Ensure Redis is running before production setup
    sudo systemctl restart redis-server || true
    sleep 2

    # Run bench setup production with error handling to prevent script exit
    if sudo -u frappe bash -c "cd '$INSTALL_PATH/frappe-bench' && bench setup production frappe"; then
        log "Bench production setup completed successfully"
    else
        warning "Bench production setup encountered issues. Services may need manual configuration."
        warning "You can try running: sudo -u frappe bench setup production frappe"
        warning "Or manually configure services with: sudo supervisorctl reread && sudo supervisorctl update"
    fi

    success "$success_msg"
}

# Configure Nginx
# Настроить Nginx
configure_nginx() {
    if [[ "$LANG" == "ru" ]]; then
        log "Настройка Nginx для ERPNext..."
        success_msg="Nginx настроен"
    else
        log "Configuring Nginx for ERPNext..."
        success_msg="Nginx configured"
    fi

    # Create nginx site configuration
    sudo tee /etc/nginx/sites-available/$DEFAULT_SITE_NAME >/dev/null <<EOF
server {
    listen 80;
    server_name $DEFAULT_SITE_NAME;

    root $INSTALL_PATH/frappe-bench/sites;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    index index.php index.html index.htm;

    location /assets {
        access_log off;
        expires 1M;
        add_header Cache-Control "public, immutable";
    }

    location ~* /(app|api|files|private) {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }

    location / {
        try_files \$uri \$uri/ =404;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    error_page 404 /404.html;
    location = /40x.html {
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
    }
}
EOF

    # Enable the site
    sudo ln -sf /etc/nginx/sites-available/$DEFAULT_SITE_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default

    # Test nginx configuration
    if sudo nginx -t; then
        log "Nginx configuration is valid"
    else
        error "Nginx configuration is invalid"
    fi

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

    # Configure Nginx
    configure_nginx

    # Enable and start services
    sudo systemctl enable nginx
    sudo systemctl enable supervisor
    sudo systemctl enable redis-server

    # Start services
    sudo systemctl start nginx || true
    sudo systemctl start supervisor || true
    sudo systemctl start redis-server || true

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
    SCRIPT_START_TIME=$(date +%s)
    log_system_info

    # Select language
    select_language

    if [[ "$LANG" == "ru" ]]; then
        log "Запуск установки ERPNext..."
        start_msg="Установка ERPNext завершена. Проверьте файл erpnext_install_summary.txt для следующих шагов."
    else
        log "Starting ERPNext installation..."
        start_msg="ERPNext installation completed. Please check the summary file for next steps."
    fi

    log_step_start "Проверка системных требований"
    check_root
    log_step_end "Проверка системных требований"

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

    # Prompt for site name if not set via environment variable
    if [[ -z "$DEFAULT_SITE_NAME" || "$DEFAULT_SITE_NAME" == "site1.local" ]]; then
        if [[ "$LANG" == "ru" ]]; then
            read -p "Введите имя сайта (по умолчанию: site1.local): " user_site_name
        else
            read -p "Enter site name (default: site1.local): " user_site_name
        fi
        DEFAULT_SITE_NAME="${user_site_name:-site1.local}"
    fi

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
