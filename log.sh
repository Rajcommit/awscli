#!/bin/bash
set -euxo pipefail

LOG="/var/log/devops-full-debug.log"
exec > >(tee -a "$LOG") 2>&1

echo "==========================="
echo "🔍 FULL DEVOPS DEBUG REPORT"
echo "Started at: $(date)"
echo "Hostname: $(hostname)"
echo "==========================="

section() {
  echo -e "\n\n============================="
  echo "🔹 $1"
  echo "============================="
}

# Basic Info
section "INSTANCE DATE & TIME"
date
uptime
timedatectl

section "EC2 INSTANCE METADATA"
curl -s http://169.254.169.254/latest/meta-data/ || echo "⚠️ Not an EC2 instance?"

section "DISK USAGE"
df -hT
du -sh /var/*

section "MEMORY STATUS"
free -m
vmstat 1 5

# OS and packages
section "OS RELEASE"
cat /etc/os-release

section "INSTALLED PACKAGES"
dnf list installed

# Services
section "SYSTEMD SERVICES (FAILED)"
systemctl --failed

section "SYSTEMD STATUS: httpd"
systemctl status httpd || true

section "SYSTEMD STATUS: php-fpm (if exists)"
systemctl status php-fpm || echo "php-fpm not found"

section "FIREWALLD STATUS"
systemctl status firewalld || echo "Firewalld not installed"
firewall-cmd --list-all || true

# SELinux
section "SELINUX STATUS"
getenforce
sestatus || true

# Apache logs
section "HTTPD ERROR LOG"
tail -n 100 /var/log/httpd/error_log || echo "No error log"

section "HTTPD ACCESS LOG"
tail -n 100 /var/log/httpd/access_log || echo "No access log"

# PHP
section "PHP VERSION & MODULES"
php -v || echo "PHP not found"
php -m || true

section "PHP CONFIG FILE"
php --ini || true

# User Data & Init Logs
section "USER-DATA OUTPUT"
cat /var/log/user-data.log || echo "No user-data.log"

section "CLOUD-INIT LOGS"
cat /var/log/cloud-init.log || echo "No cloud-init.log"
cat /var/log/cloud-init-output.log || echo "No cloud-init-output.log"

# Cron jobs
section "CRON JOBS"
crontab -l || echo "No crontab"
ls -l /etc/cron.* /var/spool/cron || true

# Directory & permissions
section "WEB DIRECTORY STRUCTURE"
ls -alR /var/www/html

# Ping & connectivity
section "PING GOOGLE (DNS, network test)"
ping -c 4 google.com || echo "Ping failed"

section "CURL TESTS (localhost + IP)"
curl -I localhost || echo "Localhost HTTP fail"
curl -I 127.0.0.1 || echo "127.0.0.1 HTTP fail"

section "PHPINFO OUTPUT (http)"
echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
curl -s http://localhost/phpinfo.php | grep -i php || echo "PHP not responding via HTTP"

# RDS Connectivity Test
section "RDS MYSQL CONNECTIVITY TEST"
RDS_HOST="your-rds-endpoint.rds.amazonaws.com"
RDS_USER="admin"
RDS_PASS="your-password"
RDS_DB="comicsdb"

mysql -h "$RDS_HOST" -u "$RDS_USER" -p"$RDS_PASS" -e "SELECT NOW();" || echo "❌ RDS Connection failed"
mysql -h "$RDS_HOST" -u "$RDS_USER" -p"$RDS_PASS" -D "$RDS_DB" -e "SHOW TABLES;" || echo "❌ RDS DB access failed"

# DNS resolution
section "DNS CHECKS"
cat /etc/resolv.conf
nslookup google.com || echo "❌ DNS resolution failed"

# Network config
section "IP ADDRESSES"
ip addr show

section "ROUTING TABLE"
ip route show

section "LISTENING PORTS"
ss -tulpen

# Open Files & Processes
section "TOP 20 MEMORY PROCESSES"
ps aux --sort=-%mem | head -n 20

section "TOP 20 CPU PROCESSES"
ps aux --sort=-%cpu | head -n 20

# NTP
section "NTP TIME SYNC"
timedatectl status | grep -i ntp || echo "NTP info unavailable"

# Optional: database seeding check
section "DATABASE TABLE CONTENTS: comics"
mysql -h "$RDS_HOST" -u "$RDS_USER" -p"$RDS_PASS" -D "$RDS_DB" -e "SELECT * FROM comics LIMIT 5;" || echo "❌ No comics data?"

# Last part
section "LOG COMPLETE"
echo "📦 All data saved to: $LOG"
