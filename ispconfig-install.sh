#!/bin/bash
set -e

LOG=/var/www/ispconfig-install.log
exec > "$LOG" 2>&1
set -x
trap 'echo "SCRIPT EXITED code=$? at $(date -u +%FT%TZ)" >> "$LOG"' EXIT

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpw}"
ISP_DB_PASSWORD="${ISP_DB_PASSWORD:-isppw}"
VER="${ISP_CONFIG_VERSION:-3.2.12p1}"
PHP_VERSION="${PHP_VERSION:-8.4}"

echo "==> Waiting for MariaDB socket"
for i in $(seq 1 60); do
    [ -S /run/mysqld/mysqld.sock ] && break
    sleep 1
done
systemctl start mariadb.service || true

echo "==> Setting MariaDB root password"
mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${MYSQL_ROOT_PASSWORD}');
FLUSH PRIVILEGES;
SQL

echo "==> Writing autoinstall.ini credentials"
sed -i \
  -e "s/__MYSQL_ROOT_PASSWORD__/${MYSQL_ROOT_PASSWORD}/g" \
  -e "s/__ISP_DB_PASSWORD__/${ISP_DB_PASSWORD}/g" \
  /etc/ispconfig/autoinstall.ini

echo "==> Downloading ISPConfig ${VER}"
cd /tmp
wget -q "https://www.ispconfig.org/downloads/ISPConfig-${VER}.tar.gz"
tar xfz "ISPConfig-${VER}.tar.gz"
cd ispconfig3_install/install

echo "==> Running ISPConfig autoinstaller (takes several minutes)"
php -q install.php --autoinstall=/etc/ispconfig/autoinstall.ini

touch /usr/local/ispconfig/ispconfig_installed
echo "==> ISPConfig installed"

systemctl disable ispconfig-install.service || true
rm -f /etc/systemd/system/multi-user.target.wants/ispconfig-install.service
echo "==> Done"
