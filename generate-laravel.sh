#!/bin/bash

# =====================================
# Laravel Docker Generator
# =====================================

# ---------- Logging ----------
log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# ---------- Header ----------
clear

echo "========================================"
echo " Laravel Docker Generator"
echo "========================================"
echo ""

# ---------- Input ----------
read -p "Masukkan username        : " USER_NAME
WEBSITE_NAME="laravel"
read -p "Masukkan port            : " PORT
PORT_WWW=$((PORT + 1))

# ---------- Validasi ----------
if [ -z "$USER_NAME" ] || [ -z "$WEBSITE_NAME" ] || [ -z "$PORT" ]; then

    log_error "Semua input wajib diisi"

    exit 1
fi

# ---------- Konfigurasi ----------
BASE_DIR="/home/yopa/Documents"

PROJECT_NAME="website_${USER_NAME}_${WEBSITE_NAME}"

PROJECT_DIR="${BASE_DIR}/${PROJECT_NAME}"

WWW_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/laravel"
WWW_HTML_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/www" # <-- TAMBAHKAN BARIS INI

APP_CONTAINER="${USER_NAME}_laravel_container"

NGINX_CONTAINER="${USER_NAME}_nginx_laravel_container"

NETWORK_NAME="laravel-net-${USER_NAME}_laravel"

HOST_UID=$(id -u)

HOST_GID=$(id -g)

# ---------- Info ----------
echo ""

log_info "Konfigurasi project"

echo "User          : ${USER_NAME}"
echo "Website       : ${WEBSITE_NAME}"
echo "Port          : ${PORT}"
echo "Project Dir   : ${PROJECT_DIR}"
echo "WWW Dir       : ${WWW_DIR}"

echo ""

# =====================================
# Create Folder
# =====================================

log_info "Membuat struktur folder..."

mkdir -p "${PROJECT_DIR}/docker-config/nginx"

if [ $? -ne 0 ]; then

    log_error "Gagal membuat folder"

    exit 1
fi

log_success "Folder berhasil dibuat"

# =====================================
# docker-compose.yml
# =====================================

log_info "Membuat docker-compose.yml..."

cat > "${PROJECT_DIR}/docker-compose.yml" <<EOF
services:

  app:
    image: nusantara-php84:1.0

    container_name: ${APP_CONTAINER}

    user: "${HOST_UID}:${HOST_GID}"

    restart: unless-stopped

    working_dir: /var/www

    volumes:
      - ${WWW_DIR}:/var/www
      - ${WWW_HTML_DIR}:/var/www_html # <-- TAMBAHKAN MOUNT INI

    networks:
      - ${NETWORK_NAME}
      - mariadb-shared-net

  nginx:
    image: nginx:alpine

    container_name: ${NGINX_CONTAINER}

    restart: unless-stopped

    ports:
      - "${PORT}:80"
      - "${PORT_WWW}:${PORT_WWW}" # <-- TAMBAHKAN PORT BARU INI

    volumes:
      - ${WWW_DIR}:/var/www
      - ${WWW_HTML_DIR}:/var/www_html # <-- TAMBAHKAN MOUNT INI
      - ./docker-config/nginx:/etc/nginx/conf.d

    networks:
      - ${NETWORK_NAME}

networks:

  ${NETWORK_NAME}:
    driver: bridge

  mariadb-shared-net:
    external: true
    name: net-phpmyadmin_shared
EOF

log_success "docker-compose.yml berhasil dibuat"

# =====================================
# nginx default.conf
# =====================================

log_info "Membuat nginx default.conf..."

cat > "${PROJECT_DIR}/docker-config/nginx/default.conf" <<EOF
server {

    listen 80;

    index index.php index.html;

    root /var/www/public;

    location ~ \\.php$ {

        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\\.php)(/.+)$;

        fastcgi_pass app:9000;

        fastcgi_index index.php;

        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location / {

        try_files \$uri \$uri/ /index.php?\$query_string;

        gzip_static on;
    }
}
EOF

log_success "default.conf berhasil dibuat"

# =====================================
# nginx www.conf
# =====================================

log_info "Membuat nginx www.conf..."

cat > "${PROJECT_DIR}/docker-config/nginx/www.conf" <<EOF
server {

    listen ${PORT_WWW};

    index index.php index.html index.htm;

    root /var/www_html;

    location ~ \\.php$ {

        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\\.php)(/.+)$;

        fastcgi_pass app:9000;

        fastcgi_index index.php;

        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location / {

        try_files \$uri \$uri/ /index.php?\$query_string;

        gzip_static on;
    }
}
EOF

log_success "www.conf berhasil dibuat"

# =====================================
# README.md
# =====================================

log_info "Membuat README.md..."

cat > "${PROJECT_DIR}/README.md" <<EOF
# Laravel Docker Deploy

## Informasi

| Item | Value |
|---|---|
| User | ${USER_NAME} |
| Website | ${WEBSITE_NAME} |
| Port | ${PORT} |

---

## Database (External)

Silakan gunakan konfigurasi database MariaDB pusat kamu. Gunakan nama container MariaDB pusat sebagai DB Host di file \`.env\` Laravel kamu.

---

## Jalankan Docker

\`\`\`bash
docker compose up -d
\`\`\`

---

## Stop Docker

\`\`\`bash
docker compose down
\`\`\`

---

## Masuk Container App

\`\`\`bash
docker exec -it ${APP_CONTAINER} sh
\`\`\`

---

## Struktur Folder

\`\`\`
${PROJECT_NAME}
├── docker-compose.yml
├── README.md
└── docker-config
    └── nginx
        └── default.conf
\`\`\`
EOF

log_success "README.md berhasil dibuat"

# =====================================
# Docker Up
# =====================================

echo ""

log_info "Menjalankan docker compose..."

cd "${PROJECT_DIR}"

sudo docker compose up -d

if [ $? -ne 0 ]; then

    log_error "Docker gagal dijalankan"

    exit 1
fi

# =====================================
# Final
# =====================================

echo ""

echo "========================================"

log_success "Laravel project berhasil dibuat"

echo "========================================"

echo ""

echo "Project : ${PROJECT_DIR}"

echo ""

log_success "Selesai"
