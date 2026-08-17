#!/bin/bash

# =====================================
# CodeIgniter 3 Docker Generator (FileBrowser Target & Git Support)
# =====================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/port.csv"

# ---------- Logging ----------
log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_error() { echo "[ERROR] $1"; }

# ---------- Header ----------
[ -t 1 ] && clear
echo "========================================"
echo " CodeIgniter 3 Docker Generator"
echo "========================================"
echo ""

# ---------- Input (CLI args atau interaktif) ----------
USER_NAME="${1:-}"
GITHUB_REPO="${2:-}"

if [ -z "$USER_NAME" ]; then
    if [ -t 0 ]; then
        read -p "Masukkan username            : " USER_NAME
    else
        log_error "Username wajib diisi (argumen pertama)"
        exit 1
    fi
fi

WEBSITE_NAME="ci3"

if [ -z "$GITHUB_REPO" ] && [ -t 0 ]; then
    read -p "Masukkan Repo GitHub (opsional): " GITHUB_REPO
fi

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
WWW_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/ci3"
WWW_HTML_DIR="/home/yopa/filebrowser/data/users/${USER_NAME}/www"
APP_CONTAINER="${USER_NAME}_ci3_container"
NGINX_CONTAINER="${USER_NAME}_nginx_ci3_container"
NETWORK_NAME="ci3-net-${USER_NAME}_ci3"
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# ---------- Info ----------
echo ""
log_info "Konfigurasi project"
echo "User          : ${USER_NAME}"
echo "Website       : ${WEBSITE_NAME}"
echo "Port CI3      : ${PORT}"
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
    if [ -d "$WWW_DIR" ] && [ "$(ls -A "$WWW_DIR" 2>/dev/null)" ]; then
        log_error "Folder ${WWW_DIR} sudah ada dan tidak kosong. Generate hanya bisa dilakukan sekali per user/framework."
        exit 1
    fi
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
fi

mkdir -p "${WWW_HTML_DIR}"
log_success "Struktur folder berhasil disiapkan"

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
    root /var/www;

    # Proteksi folder sensitif CodeIgniter 3
    location ~ ^/(application|system) {
        deny all;
        return 404;
    }

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
    echo "1) Full Setup (Composer Install)"
    echo "2) Run Composer Install"
    echo "3) Run Custom Script / Command (bebas)"
    read -p "Pilihan [1-3]: " CHOICE
fi

case \$CHOICE in
    1|2)
        echo "[INFO] Running composer install..."
        docker exec "\${CONTAINER_NAME}" composer install
        ;;

    3)
        CUSTOM_CMD="\$EXTRA_PARAM"
        if [ -z "\$CUSTOM_CMD" ] && [ -t 0 ]; then
            read -p "Masukkan perintah/script (misal: php check_tables.php): " CUSTOM_CMD
        fi

        if [ -n "\$CUSTOM_CMD" ]; then
            docker exec "\${CONTAINER_NAME}" \$CUSTOM_CMD
        else
            echo "[ERROR] Perintah tidak boleh kosong."
            exit 1
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
# CodeIgniter 3 Docker Deploy

## Informasi

| Item | Value |
|---|---|
| User | ${USER_NAME} |
| Website | ${WEBSITE_NAME} |
| Port App | ${PORT} |
| Port WWW | ${PORT_WWW} |
| Source Dir (FileBrowser) | ${WWW_DIR} |

---

## Database (External)

Silakan gunakan konfigurasi database MariaDB pusat kamu. Gunakan nama container MariaDB pusat sebagai DB Host di file \`application/config/database.php\` CodeIgniter 3 kamu.

---

## Helper Exec & Build

Jalankan script \`./build.sh\` di direktori ini untuk menjalankan composer install atau custom script:

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
EOF

log_success "README.md berhasil dibuat"

# (Port sudah dicatat ke port.csv secara atomik saat alokasi di awal script)

# =====================================
# Docker Up
# =====================================
echo ""
log_info "Menjalankan docker compose..."

cd "${PROJECT_DIR}"

docker compose up -d

if [ $? -ne 0 ]; then
    log_error "Docker gagal dijalankan"
    exit 1
fi

# =====================================
# Final
# =====================================
echo ""
echo "========================================"
log_success "CodeIgniter 3 project berhasil dibuat"
echo "========================================"
echo ""
echo "Project Dir   : ${PROJECT_DIR}"
echo "Source Dir    : ${WWW_DIR} (FileBrowser)"
echo "Port App      : ${PORT}"
echo "Port WWW      : ${PORT_WWW}"
echo "Helper        : ${PROJECT_DIR}/build.sh"
echo ""
log_success "Selesai"
