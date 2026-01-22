# Universal Frappe/ERPNext Installation Script

Этот скрипт автоматически устанавливает Frappe Framework и ERPNext v15 с нуля на поддерживаемых дистрибутивах Linux в режиме production (Nginx + Supervisor).

## Поддерживаемые ОС

- Ubuntu (18.04+)
- Debian (10+)
- RHEL (8+)
- Oracle Linux (8+)
- CentOS/Rocky Linux/AlmaLinux

## Что устанавливает скрипт

1. **Системные зависимости**: Python 3.10+, Node.js 18+, Yarn, Redis, MariaDB, Nginx, Supervisor, wkhtmltopdf, bmon, mc, htop, vim, nano, screen, rsync, unzip, redis-tools и другие
2. **MariaDB**: Настраивает сервер БД с пользователем frappe
3. **Frappe Bench**: Устанавливает инструмент bench для управления Frappe
4. **ERPNext v15**: Создает новый сайт с установленным ERPNext
5. **Production setup**: Настраивает Nginx и Supervisor для production развертывания

## Требования

- Чистая система (без предварительно установленного Frappe)
- Права sudo (скрипт не должен запускаться от root)
- Интернет-соединение для загрузки пакетов

## Использование

### Базовый запуск (с настройками по умолчанию)

```bash
git clone <this-repo>
cd script-erpnext-install
./install_erpnext.sh
```

**Примечание:** Скрипт поддерживает выбор языка (английский/русский) в начале установки.

### С кастомными параметрами

Скрипт использует переменные окружения для настройки:

```bash
export SITE_NAME="mycompany.local"
export ADMIN_PASSWORD="securepassword123"
export ERP_VERSION="v15"
export FRAPPE_BRANCH="v15"
export INSTALL_PATH="/opt/frappe"
./install_erpnext.sh
```

Доступные переменные:
- `SITE_NAME`: Имя сайта (по умолчанию: site1.local)
- `ADMIN_PASSWORD`: Пароль администратора (по умолчанию: admin)
- `ERP_VERSION`: Версия ERPNext (по умолчанию: v15)
- `FRAPPE_BRANCH`: Ветка Frappe (по умолчанию: v15)
- `INSTALL_PATH`: Путь установки (по умолчанию: /opt/frappe)
- `INSTALL_MODE`: Режим установки - production или development (по умолчанию: production)

## Процесс установки

Скрипт выполняет следующие шаги:

1. **Детект ОС**: Определяет дистрибутив и настраивает менеджер пакетов
2. **Настройка Git**: Запрашивает имя пользователя и email для Git
3. **Установка зависимостей**: Устанавливает все необходимые пакеты
4. **Настройка MariaDB**: Создает пользователя frappe с паролем frappe_password
5. **Создание пользователя frappe**: Добавляет системного пользователя
6. **Установка Bench**: Инициализирует Frappe Bench
7. **Установка ERPNext**: Получает и устанавливает ERPNext
8. **Настройка сервисов**: Включает Nginx, Supervisor и Redis

## После установки

После успешной установки:

1. Добавьте запись в `/etc/hosts`:
   ```
   127.0.0.1 site1.local
   ```

2. Запустите сервисы:
   ```bash
   sudo supervisorctl start all
   ```

3. Откройте браузер и перейдите на: `http://site1.local`

4. Войдите с учетными данными:
   - Пользователь: Administrator
   - Пароль: admin (или ваш кастомный)

## Управление сервисами

```bash
# Запуск всех сервисов
sudo supervisorctl start all

# Остановка всех сервисов
sudo supervisorctl stop all

# Перезапуск сервисов
sudo supervisorctl restart all

# Просмотр статуса
sudo supervisorctl status
```

## Логи и troubleshooting

- Логи установки: `/var/log/erpnext_install.log`
- Логи приложений: `/opt/frappe/frappe-bench/logs/`
- Конфигурация Nginx: `/etc/nginx/sites-available/`

## Безопасность

- Измените пароль администратора после первого входа
- Настройте firewall (ufw/firewalld)
- Рассмотрите использование HTTPS (Let's Encrypt)
- Регулярно обновляйте систему и приложения

## Кастомизация

Для более сложных настроек отредактируйте скрипт:

- Измените пароли в разделе конфигурации MariaDB
- Добавьте дополнительные приложения через bench get-app
- Настройте дополнительные сайты

## Обновление

Для обновления ERPNext:

```bash
cd /opt/frappe/frappe-bench
bench update
```

## Поддержка

При возникновении проблем проверьте:
1. Логи установки
2. Статус сервисов: `sudo supervisorctl status`
3. Логи приложений в `/opt/frappe/frappe-bench/logs/`

## Предложения по усовершенствованию

### Исправления для конкретных дистрибутивов

**Debian 13 (Bookworm) и новее:**
- wkhtmltopdf: Добавлена поддержка snap и прямой загрузки .deb пакетов
- Python MySQL: Заменен python3-mysqldb на python3-mysql.connector для совместимости
- MariaDB: Использован ручной SQL вместо mysql_secure_installation для надежности

**RHEL/OEL 9+:**
- Добавлена поддержка AlmaLinux, Rocky Linux
- Улучшена установка EPEL и зависимостей

### Будущие улучшения

1. **Многосайтовая поддержка**: Возможность установки нескольких сайтов в одном bench
2. **SSL/HTTPS**: Автоматическая настройка Let's Encrypt
3. **Бэкапы**: Интеграция с автоматическими бэкапами
4. **Мониторинг**: Добавление Prometheus/Grafana для мониторинга
5. **Docker**: Поддержка контейнеризации
6. **CI/CD**: Интеграция с GitHub Actions для автоматического тестирования
7. **Обновления**: Автоматические обновления через cron
8. **Резервное копирование**: Встроенные инструменты бэкапа и восстановления
9. **Безопасность**: Усиление безопасности (fail2ban, SELinux, AppArmor)
10. **Локализация**: Поддержка различных языков интерфейса

### Отчет об ошибках

Если вы обнаружили проблемы:
1. Проверьте логи в `/var/log/erpnext_install.log`
2. Укажите версию ОС и дистрибутива
3. Опишите шаги воспроизведения ошибки
4. Приложите вывод команд диагностики

## Лицензия

Этот скрипт предоставляется как есть, без гарантий.
