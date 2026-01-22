#!/bin/bash

# Fix for syntax error: Properly quote strings with parentheses
# Alternative 1: Double quotes (allows variable expansion)
echo "Этот скрипт автоматически устанавливает Frappe Framework и ERPNext v15 с нуля на поддерживаемых дистрибутивах Linux в режиме production (Nginx + Supervisor)."

# Alternative 2: Single quotes (literal, no expansion)
# echo 'Этот скрипт автоматически устанавливает Frappe Framework и ERPNext v15 с нуля на поддерживаемых дистрибутивах Linux в режиме production (Nginx + Supervisor).'

# Alternative 3: Escaped parentheses
# echo "Этот скрипт автоматически устанавливает Frappe Framework и ERPNext v15 с нуля на поддерживаемых дистрибутивах Linux в режиме production \(Nginx + Supervisor\)."

# Now run the actual installation script
./install_erpnext.sh
