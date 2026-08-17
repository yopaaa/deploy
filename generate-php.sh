#!/bin/bash

# =====================================
# Native PHP / HTML / CSS Docker Generator (FileBrowser Target & Git Support)
# =====================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/port.csv"

# ---------- Logging ----------
log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_error() { echo "[ERROR] $1"; }

# ---------- Header ----------
clear
echo "========================================"
echo " Native PHP / HTML / CSS Docker Generator"
echo "========================================"
echo ""

# ---------- Input ----------
read -p "Masukkan username            : " USER_NAME
WEBSITE_NAME="php"
read -p "Masukkan Repo GitHub (opsional): " GITHUB_REPO

# ---------- Otomatisasi Port (CSV dengan File Locking) ----------
# Port dialokasikan secara atomik menggunakan flock untuk mencegah
# race condition saat multiple request API berjalan bersamaan.
allocate_port() {
    (
        flock -x 200

        if [ ! -f "$CSV_FILE" ]; then
            echo "username,framework,port_app,port_www,created_at" > "$CSV_FILE"
        fi

        _LAST_PORT=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+$/ {print $4}' "$CSV_FILE" | tail -n 1)
        if [ -n "$_LAST_PORT" ]; then
            _PORT=$((_LAST_PORT + 1))
        else
            _PORT=${1:-10000}
        fi

        _PORT_WWW=$((_PORT + 1))
        _CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
        echo "${USER_NAME},${WEBSITE_NAME},${_PORT},${_PORT_WWW},${_CREATED_AT}" >> "$CSV_FILE"

        echo "$_PORT"
    ) 200>"${CSV_FILE}.lock"
}

PORT=$(allocate_port 10000)
PORT_WWW=$((PORT + 1))
log_info "Port berhasil dialokasikan: App=${PORT}, WWW=${PORT_WWW}"

# ---------- Validasi ----------
if [ -z "$USER_NAME" ] || [ -z "$WEBSITE_NAME" ] || [ -z "$PORT" ]; then
    log_error "Semua input wajib diisi"
    exit 1
fi

# ---------- Konfigurasi ----------
BASE_DIR="/home/yopa/Documents"
PROJECT_NAME="website_${USER_NAME}_${WEBSITE_NAME}"
PROJECT_DIR="${BASE_DIR}/${PROJECT_NAME}"
WWW_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/php"
WWW_HTML_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/www"
APP_CONTAINER="${USER_NAME}_php_container"
NGINX_CONTAINER="${USER_NAME}_nginx_php_container"
NETWORK_NAME="php-net-${USER_NAME}_php"
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# ---------- Info ----------
echo ""
log_info "Konfigurasi project"
echo "User          : ${USER_NAME}"
echo "Website       : ${WEBSITE_NAME}"
echo "Port PHP/App  : ${PORT}"
echo "Port WWW      : ${PORT_WWW}"
echo "Project Dir   : ${PROJECT_DIR}"
echo "Source Dir    : ${WWW_DIR} (FileBrowser)"
echo "WWW HTML Dir  : ${WWW_HTML_DIR} (FileBrowser)"
echo ""

# =====================================
# Setup Directory & Git Clone
# =====================================
mkdir -p "${PROJECT_DIR}/docker-config/nginx"

if [ -n "$GITHUB_REPO" ]; then
    log_info "Cloning repository GitHub ke FileBrowser: ${WWW_DIR}..."
    mkdir -p "$(dirname "$WWW_DIR")"
    git clone "$GITHUB_REPO" "$WWW_DIR"
    if [ $? -ne 0 ]; then
        log_error "Gagal me-clone repository GitHub."
        exit 1
    fi
else
    log_info "Membuat direktori source di FileBrowser: ${WWW_DIR}..."
    mkdir -p "$WWW_DIR"
    if [ ! -f "${WWW_DIR}/index.php" ] && [ ! -f "${WWW_DIR}/index.html" ]; then
        cat > "${WWW_DIR}/index.php" <<'EOF'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Selamat Datang di Web PHP</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8fafc; color: #1e293b; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
        .card { background: white; padding: 2.5rem; border-radius: 12px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); max-width: 500px; width: 100%; text-align: center; }
        h1 { color: #0f172a; margin-bottom: 0.5rem; }
        p { color: #64748b; line-height: 1.5; }
        .badge { display: inline-block; background: #e0e7ff; color: #4338ca; padding: 0.25rem 0.75rem; border-radius: 9999px; font-size: 0.875rem; font-weight: 600; margin-top: 1rem; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🚀 Web PHP Berjalan Sukses!</h1>
        <p>Silakan upload atau edit file HTML, CSS, dan PHP Anda melalui FileBrowser.</p>
        <span class="badge">PHP Version: <?php echo phpversion(); ?></span>
    </div>
</body>
</html>
EOF
    fi
fi

mkdir -p "${WWW_HTML_DIR}"
if [ ! -f "${WWW_HTML_DIR}/index.html" ]; then
    cat > "${WWW_HTML_DIR}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>Web Statis (WWW)</title>
    <style>
        body { font-family: sans-serif; text-align: center; padding: 50px; background: #f1f5f9; }
    </style>
</head>
<body>
    <h2>📁 Web Statis (Port WWW)</h2>
    <p>Letakkan file HTML/CSS/JS statis Anda di folder <code>www/</code> FileBrowser.</p>
</body>
</html>
EOF
fi

log_success "Struktur folder & file starter berhasil disiapkan"

# =====================================
# docker-compose.yml
# =====================================
log_info "Membuat docker-compose.yml..."
cat > "${PROJECT_DIR}/docker-compose.yml" <<EOF
services:

  app:
    image: nusantara-php84-native:1.0
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
    index index.php index.html index.htm;
    root /var/www;

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
# build.sh (Helper Script Lokal per Project - Standar 1-5 Native PHP)
# =====================================
log_info "Membuat build.sh khusus di ${PROJECT_DIR}..."

cat > "${PROJECT_DIR}/build.sh" <<EOF
#!/bin/bash

CONTAINER_NAME="${APP_CONTAINER}"

CHOICE="\$1"
EXTRA_PARAM="\$2"

if [ -z "\$CHOICE" ]; then
    clear
    echo "========================================"
    echo " Helper Tool - ${PROJECT_NAME}"
    echo " Container  : \${CONTAINER_NAME}"
    echo "========================================"
    echo ""
    echo "Pilih tindakan yang ingin dijalankan:"
    echo "1) Full Setup / Status Check"
    echo "2) Run Composer Install (jika ada composer.json)"
    echo "3) Run Database / SQL Script"
    echo "4) Run Database Seeder"
    echo "5) Run Custom PHP Script / Command (bebas)"
    read -p "Pilihan [1-5]: " CHOICE
fi

case \$CHOICE in
    1)
        echo "[INFO] Native PHP tidak memerlukan build khusus."
        echo "[SUCCESS] Status Container: Aktif dan siap melayani file PHP/HTML/CSS."
        ;;

    2)
        echo "[INFO] Running composer install..."
        docker exec "\${CONTAINER_NAME}" composer install 2>/dev/null || echo "[INFO] composer.json tidak ditemukan, dilewati."
        ;;

    3|4|5)
        CUSTOM_CMD="\$EXTRA_PARAM"
        if [ -z "\$CUSTOM_CMD" ] && [ -t 0 ]; then
            read -p "Masukkan perintah PHP/Script (misal: php test.php): " CUSTOM_CMD
        fi

        if [ -n "\$CUSTOM_CMD" ]; then
            docker exec "\${CONTAINER_NAME}" \$CUSTOM_CMD
        else
            echo "[INFO] Tidak ada perintah yang dijalankan."
        fi
        ;;

    *)
        echo "[ERROR] Pilihan '\$CHOICE' tidak valid."
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
# Native PHP / HTML / CSS Docker Deploy

## Informasi

| Item | Value |
|---|---|
| User | ${USER_NAME} |
| Website | ${WEBSITE_NAME} |
| Port PHP App | ${PORT} |
| Port WWW | ${PORT_WWW} |
| Source Dir (FileBrowser) | ${WWW_DIR} |

---

## Database (External)

Silakan gunakan konfigurasi database MariaDB pusat kamu. Gunakan \`mariadb_container\` sebagai DB Host pada koneksi \`mysqli\` atau \`PDO\` Anda.

---

## Helper Exec & Build

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
EOF

log_success "README.md berhasil dibuat"

# (Port sudah dicatat ke port.csv secara atomik saat alokasi di awal script)

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
log_success "Native PHP / HTML / CSS project berhasil dibuat"
echo "========================================"
echo ""
echo "Project Dir   : ${PROJECT_DIR}"
echo "Source Dir    : ${WWW_DIR} (FileBrowser)"
echo "Port PHP      : ${PORT}"
echo "Port WWW      : ${PORT_WWW}"
echo "Helper        : ${PROJECT_DIR}/build.sh"
echo ""
log_success "Selesai"
