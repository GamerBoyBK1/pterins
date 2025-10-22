#!/bin/bash
set -e

echo ""
echo "🦇 Pterodactyl Panel Auto Installer (Backend Only)"
echo "-----------------------------------------------"

read -p "Enter a strong MySQL password for Pterodactyl DB user: " DB_PASS
read -p "Enter Admin Email: " ADMIN_EMAIL
read -p "Enter Admin Username: " ADMIN_USER
read -p "Enter Admin First Name: " ADMIN_FIRST
read -p "Enter Admin Last Name: " ADMIN_LAST
read -s -p "Enter Admin Password: " ADMIN_PASS
echo ""

apt update -y && apt upgrade -y
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg mariadb-server redis-server git unzip tar

LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}

mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
cp .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
php artisan key:generate --force

mysql -u root -e "CREATE DATABASE panel;"
mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env

php artisan migrate --seed --force
php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name="$ADMIN_FIRST $ADMIN_LAST" --password="$ADMIN_PASS" --admin=1

chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl

cat <<EOF >/etc/systemd/system/pteroq.service
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now redis-server
systemctl enable --now pteroq.service

echo ""
echo "✅ Installation Complete!"
echo "-----------------------------------------------"
echo "🔹 MySQL User: pterodactyl"
echo "🔹 MySQL Password: ${DB_PASS}"
echo "🔹 Panel Directory: /var/www/pterodactyl"
echo "-----------------------------------------------"
echo "🎉 Done! Configure your Nginx or Apache for the panel."
