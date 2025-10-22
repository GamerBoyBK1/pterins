#!/bin/bash
set -e

echo ""
echo "🦇 Pterodactyl Panel Auto Installer (Full Backend + SSL + Nginx)"
echo "---------------------------------------------------------------"

# 🧠 Collect user input
read -p "Enter a strong MySQL password for Pterodactyl DB user: " DB_PASS
read -p "Enter Admin Email: " ADMIN_EMAIL
read -p "Enter Admin Username: " ADMIN_USER
read -p "Enter Admin First Name: " ADMIN_FIRST
read -p "Enter Admin Last Name: " ADMIN_LAST
read -s -p "Enter Admin Password: " ADMIN_PASS
echo ""

# 🧱 Update system
apt update -y && apt upgrade -y

# ⚙️ Install required packages
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release unzip tar git openssl

# 🧩 Install MariaDB & Redis
apt -y install mariadb-server redis-server

# 🧠 Add PHP repository & install PHP 8.3
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}

# 🌍 Download & extract Pterodactyl Panel
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# 🧰 Install Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
cp .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# 🗄️ Configure MariaDB for Pterodactyl
mysql -u root -e "CREATE DATABASE panel;"
mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# 🧾 Update .env database settings
sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env

# 🧠 Run migrations & seeders
php artisan migrate --seed --force

# 👑 Create admin user (fixed for new Pterodactyl)
php artisan p:user:make \
  --email="$ADMIN_EMAIL" \
  --username="$ADMIN_USER" \
  --first-name="$ADMIN_FIRST" \
  --last-name="$ADMIN_LAST" \
  --password="$ADMIN_PASS" \
  --admin=1

# 📁 Permissions
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl

# 🔒 Generate self-signed SSL certificate
echo ""
echo "🔐 Generating self-signed SSL certificate..."
mkdir -p /etc/certs
cd /etc/certs
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
  -subj "/C=NA/ST=NA/L=NA/O=NA/CN=Generic SSL Certificate" \
  -keyout privkey.pem -out fullchain.pem
echo "✅ SSL created at /etc/certs/"

# ⚙️ Create Queue Worker service
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

# 🔁 Enable Redis + Queue Worker
systemctl enable --now redis-server
systemctl enable --now pteroq.service

# 🌐 Nginx Setup
echo ""
echo "🌐 Setting up Nginx configuration..."
apt install -y nginx

read -p "Enter your Panel Domain (e.g., panel.example.com): " PANEL_DOMAIN

tee /etc/nginx/sites-available/pterodactyl.conf > /dev/null <<EOF
server_tokens off;

server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${PANEL_DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    access_log /var/log/nginx/pterodactyl.access.log;
    error_log /var/log/nginx/pterodactyl.error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    ssl_certificate /etc/certs/fullchain.pem;
    ssl_certificate_key /etc/certs/privkey.pem;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS on;
        fastcgi_read_timeout 120s;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t && systemctl restart nginx

# ✅ Final message
echo ""
echo "✅ Installation Complete!"
echo "----------------------------------------------------------"
echo "🔹 MySQL User: pterodactyl"
echo "🔹 MySQL Password: ${DB_PASS}"
echo "🔹 Panel Directory: /var/www/pterodactyl"
echo "🔹 SSL Cert Path: /etc/certs/fullchain.pem"
echo "🔹 SSL Key Path:  /etc/certs/privkey.pem"
echo "🔹 Visit: https://${PANEL_DOMAIN}"
echo "----------------------------------------------------------"
echo "🎉 Done! Pterodactyl Panel Backend Installed Successfully."
