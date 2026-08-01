#!/bin/bash

# =====================================
# CodeIgniter 4 Docker Generator
# =====================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/port.csv"

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
echo " CodeIgniter 4 Docker Generator"
echo "========================================"
echo ""

# ---------- Input ----------
read -p "Masukkan username        : " USER_NAME
WEBSITE_NAME="ci4"

# ---------- Otomatisasi Port (CSV) ----------
if [ ! -f "$CSV_FILE" ]; then
    echo "username,framework,port_app,port_www,created_at" > "$CSV_FILE"
fi

PORT=""
if [ -s "$CSV_FILE" ]; then
    LAST_PORT=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+$/ {print $4}' "$CSV_FILE" | tail -n 1)
    if [ -n "$LAST_PORT" ]; then
        PORT=$((LAST_PORT + 1))
        log_info "Port otomatis terdeteksi dari ${CSV_FILE} (Terakhir: ${LAST_PORT}) -> Port Baru: ${PORT}"
    fi
fi

if [ -z "$PORT" ]; then
    read -p "Masukkan port awal (default 10000): " INPUT_PORT
    PORT=${INPUT_PORT:-10000}
fi

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
WWW_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/ci4"
WWW_HTML_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/www"
APP_CONTAINER="${USER_NAME}_ci4_container"
NGINX_CONTAINER="${USER_NAME}_nginx_ci4_container"
NETWORK_NAME="ci4-net-${USER_NAME}_ci4"
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# ---------- Info ----------
echo ""
log_info "Konfigurasi project"
echo "User          : ${USER_NAME}"
echo "Website       : ${WEBSITE_NAME}"
echo "Port CI4      : ${PORT}"
echo "Port WWW      : ${PORT_WWW}"
echo "Project Dir   : ${PROJECT_DIR}"
echo "WWW Dir       : ${WWW_DIR}"
echo "WWW HTML Dir  : ${WWW_HTML_DIR}"
echo ""

# =====================================
# Create Folder & Permission Pre-set
# =====================================
log_info "Membuat struktur folder & mengatur izin akses..."
mkdir -p "${PROJECT_DIR}/docker-config/nginx"
mkdir -p "${WWW_DIR}/writable/cache"
mkdir -p "${WWW_DIR}/writable/logs"
mkdir -p "${WWW_DIR}/writable/session"
mkdir -p "${WWW_DIR}/writable/uploads"
mkdir -p "${WWW_DIR}/writable/debugbar"
mkdir -p "${WWW_HTML_DIR}"

# Set izin writable penuh untuk folder writable CI4
chmod -R 777 "${WWW_DIR}/writable" 2>/dev/null || true

if [ $? -ne 0 ]; then
    log_error "Gagal membuat folder"
    exit 1
fi

log_success "Folder & Izin Writable CI4 berhasil dibuat"

# =====================================
# docker-compose.yml
# =====================================
log_info "Membuat docker-compose.yml..."
cat > "${PROJECT_DIR}/docker-compose.yml" <<EOF
services:

  app:
    image: nusantara-php84-ci:1.0
    container_name: ${APP_CONTAINER}
    user: "${HOST_UID}:${HOST_GID}"
    restart: unless-stopped
    working_dir: /var/www
    volumes:
      - ${WWW_DIR}:/var/www
      - ${WWW_HTML_DIR}:/var/www_html
    networks:
      - ${NETWORK_NAME}
      - mariadb-shared-net

  nginx:
    image: nginx:alpine
    container_name: ${NGINX_CONTAINER}
    restart: unless-stopped
    ports:
      - "${PORT}:80"
      - "${PORT_WWW}:${PORT_WWW}"
    volumes:
      - ${WWW_DIR}:/var/www
      - ${WWW_HTML_DIR}:/var/www_html
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
# build.sh (Helper Script Lokal per Project)
# =====================================
log_info "Membuat build.sh khusus di ${PROJECT_DIR}..."

cat > "${PROJECT_DIR}/build.sh" <<EOF
#!/bin/bash

CONTAINER_NAME="${APP_CONTAINER}"
WWW_DIR="${WWW_DIR}"

clear
echo "========================================"
echo " Helper Tool - ${PROJECT_NAME}"
echo " Container  : \${CONTAINER_NAME}"
echo "========================================"
echo ""

echo "Pilih tindakan yang ingin dijalankan:"
echo "1) Full Setup (Permissions + .env + Composer Install)"
echo "2) Run Composer Install"
echo "3) Run Database Migration (php spark migrate)"
echo "4) Run Database Seeder (php spark db:seed)"
echo "5) Run Custom Command / Script (bebas)"
read -p "Pilihan [1-5]: " CHOICE

case \$CHOICE in
    1)
        echo "[INFO] Mengatur folder writable..."
        mkdir -p "\${WWW_DIR}/writable/cache" "\${WWW_DIR}/writable/logs" "\${WWW_DIR}/writable/session" "\${WWW_DIR}/writable/uploads" "\${WWW_DIR}/writable/debugbar"
        chmod -R 777 "\${WWW_DIR}/writable" 2>/dev/null || true

        if [ -f "\${WWW_DIR}/env" ] && [ ! -f "\${WWW_DIR}/.env" ]; then
            cp "\${WWW_DIR}/env" "\${WWW_DIR}/.env"
            sed -i 's/# CI_ENVIRONMENT = production/CI_ENVIRONMENT = development/g' "\${WWW_DIR}/.env"
            echo "[SUCCESS] File .env berhasil dibuat (Mode: development)"
        fi

        echo "[INFO] Running composer install..."
        docker exec -it "\${CONTAINER_NAME}" composer install
        echo "[SUCCESS] Full Setup Selesai!"
        ;;

    2)
        docker exec -it "\${CONTAINER_NAME}" composer install
        ;;

    3)
        docker exec -it "\${CONTAINER_NAME}" php spark migrate
        ;;

    4)
        read -p "Masukkan nama Seeder (kosongkan untuk default): " SEEDER_NAME
        if [ -n "\$SEEDER_NAME" ]; then
            docker exec -it "\${CONTAINER_NAME}" php spark db:seed "\$SEEDER_NAME"
        else
            docker exec -it "\${CONTAINER_NAME}" php spark db:seed
        fi
        ;;

    5)
        read -p "Masukkan perintah/script (misal: php check_tables.php): " CUSTOM_CMD
        if [ -n "\$CUSTOM_CMD" ]; then
            docker exec -it "\${CONTAINER_NAME}" \$CUSTOM_CMD
        else
            echo "[ERROR] Perintah tidak boleh kosong."
        fi
        ;;

    *)
        echo "[ERROR] Pilihan tidak valid."
        exit 1
        ;;
esac
EOF

chmod +x "${PROJECT_DIR}/build.sh"
log_success "build.sh berhasil dibuat di ${PROJECT_DIR}"

# =====================================
# README.md
# =====================================
log_info "Membuat README.md..."
cat > "${PROJECT_DIR}/README.md" <<EOF
# CodeIgniter 4 Docker Deploy

## Informasi

| Item | Value |
|---|---|
| User | ${USER_NAME} |
| Website | ${WEBSITE_NAME} |
| Port App | ${PORT} |
| Port WWW | ${PORT_WWW} |

---

## Database (External)

Silakan gunakan konfigurasi database MariaDB pusat kamu. Gunakan nama container MariaDB pusat sebagai DB Host di file \`.env\` CodeIgniter 4 kamu.

---

## Helper Exec & Build

Jalankan script \`./build.sh\` di direktori ini untuk menjalankan composer install, migration, seeder, atau custom script:

\`\`\`bash
./build.sh
\`\`\`

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
├── build.sh
└── docker-config
    └── nginx
        ├── default.conf
        └── www.conf
\`\`\`
EOF

log_success "README.md berhasil dibuat"

# =====================================
# Simpan Port ke port.csv
# =====================================
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
echo "${USER_NAME},${WEBSITE_NAME},${PORT},${PORT_WWW},${CREATED_AT}" >> "$CSV_FILE"
log_success "Data port berhasil dicatat ke ${CSV_FILE}"

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
log_success "CodeIgniter 4 project berhasil dibuat"
echo "========================================"
echo ""
echo "Project   : ${PROJECT_DIR}"
echo "Port App  : ${PORT}"
echo "Port WWW  : ${PORT_WWW}"
echo "Helper    : ${PROJECT_DIR}/build.sh"
echo ""
log_success "Selesai"
