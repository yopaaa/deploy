#!/bin/bash

# =======================================================
# MariaDB Auto User & Multi-Database Creator (.env Support)
# =======================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# =========================
# Logging Functions
# =========================
log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_error() { echo "[ERROR] $1"; }

# =========================
# Load Environment Variables from .env
# =========================
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

CONTAINER_NAME="${MARIADB_CONTAINER_NAME:-mariadb_container}"
ROOT_PW="${MARIADB_ROOT_PASSWORD}"
FILEBROWSER_BASE="/home/yopa/filebrowser/data/users"

if [ -z "$ROOT_PW" ]; then
    log_error "Variabel MARIADB_ROOT_PASSWORD tidak ditemukan di file .env (${ENV_FILE})"
    exit 1
fi

# Generate Random Password
generate_password() {
    openssl rand -hex 16
}

DB_USER=""
CUSTOM_DB_NAME=""

# Parsing Argumen (--user dan opsional --db)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --user) DB_USER="$2"; shift 2 ;;
        --db) CUSTOM_DB_NAME="$2"; shift 2 ;;
        *)
            if [ -z "$DB_USER" ]; then
                DB_USER="$1"
                shift
            elif [ -z "$CUSTOM_DB_NAME" ]; then
                CUSTOM_DB_NAME="$1"
                shift
            else
                echo "Argumen tidak dikenal: $1"; exit 1
            fi
            ;;
    esac
done

if [ -z "$DB_USER" ]; then
    if [ -t 0 ]; then
        echo "========================================"
        echo " MariaDB Multi-Database Creator"
        echo "========================================"
        echo ""
        read -p "Masukkan username                     : " DB_USER
        read -p "Nama Database spesifik (opsional)     : " CUSTOM_DB_NAME
    else
        log_error "Username wajib diisi (gunakan --user <nama>)"
        exit 1
    fi
fi

# Validasi
if [ -z "$DB_USER" ]; then
    log_error "Username tidak boleh kosong"
    exit 1
fi

# Tentukan Nama Database
if [ -n "$CUSTOM_DB_NAME" ]; then
    # Jika custom db name tidak diawali dengan username, tambahkan prefix agar aman & terisolasi
    if [[ "$CUSTOM_DB_NAME" == user_${DB_USER}* ]] || [[ "$CUSTOM_DB_NAME" == ${DB_USER}_* ]]; then
        DB_NAME="${CUSTOM_DB_NAME}"
    else
        DB_NAME="user_${DB_USER}_${CUSTOM_DB_NAME}"
    fi
else
    DB_NAME="user_${DB_USER}"
fi

DB_PASS=$(generate_password)
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

log_info "Membuat database '${DB_NAME}' dan user '${DB_USER}' di ${CONTAINER_NAME}..."

# Eksekusi Query ke Container MariaDB
sudo docker exec -i ${CONTAINER_NAME} mariadb -u root -p${ROOT_PW} <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF

if [ $? -ne 0 ]; then
    log_error "Gagal membuat database atau user di MariaDB"
    exit 1
fi

log_success "Database '${DB_NAME}' dan User '${DB_USER}' berhasil dibuat di MariaDB"

# =========================
# 1. Buat File Kredensial Spesifik Per Database (Tidak saling timpa)
# =========================
SPECIFIC_MD="${SCRIPT_DIR}/DATABASE_${DB_NAME}.md"

cat > "${SPECIFIC_MD}" <<EOF
# Informasi Database MariaDB (${DB_NAME})

| Item | Value |
|---|---|
| **Engine** | MariaDB |
| **DB Host** | ${CONTAINER_NAME} |
| **DB Port** | 3306 |
| **DB Name** | ${DB_NAME} |
| **DB User** | ${DB_USER} |
| **DB Password** | ${DB_PASS} |
| **Created At** | ${CREATED_AT} |

---
> ⚠️ **Catatan Penting:** Gunakan kredensial ini pada file \`.env\` project Anda.
EOF

# =========================
# 2. Salin File Spesifik & Update Master File di FileBrowser
# =========================
USER_FB_DIR="${FILEBROWSER_BASE}/${DB_USER}"
mkdir -p "$USER_FB_DIR"

# Salin file spesifik per database (misal: DATABASE_user_indah_toko.md)
DEST_SPECIFIC_MD="${USER_FB_DIR}/DATABASE_${DB_NAME}.md"
cp "${SPECIFIC_MD}" "${DEST_SPECIFIC_MD}"
chmod 666 "${DEST_SPECIFIC_MD}" 2>/dev/null || true

# Update Master File (DATABASE.md) yang mengumpulkan seluruh database user
MASTER_MD="${USER_FB_DIR}/DATABASE.md"

if [ ! -f "$MASTER_MD" ]; then
    cat > "${MASTER_MD}" <<EOF
# 🗄️ Daftar Kredensial Database (${DB_USER})

Dokumen ini berisi seluruh database yang dimiliki oleh user **${DB_USER}**.

| No | DB Name | Host | Port | User | Password | Created At |
|---|---|---|---|---|---|---|
| 1 | \`${DB_NAME}\` | \`${CONTAINER_NAME}\` | \`3306\` | \`${DB_USER}\` | \`${DB_PASS}\` | ${CREATED_AT} |
EOF
else
    # Hitung jumlah baris database yang sudah ada di tabel
    COUNT=$(grep -c "^|" "$MASTER_MD")
    INDEX=$((COUNT - 1)) # kurangi header & separator
    if [ "$INDEX" -lt 1 ]; then INDEX=1; fi
    echo "| ${INDEX} | \`${DB_NAME}\` | \`${CONTAINER_NAME}\` | \`3306\` | \`${DB_USER}\` | \`${DB_PASS}\` | ${CREATED_AT} |" >> "$MASTER_MD"
fi

chmod 666 "${MASTER_MD}" 2>/dev/null || true

log_success "Kredensial spesifik disimpan ke: ${DEST_SPECIFIC_MD}"
log_success "Master database list diperbarui di: ${MASTER_MD}"

echo ""
echo "========================================"
log_success "Kredensial Database Berhasil Dibuat:"
echo "========================================"
echo "DB_HOST     : ${CONTAINER_NAME}"
echo "DB_DATABASE : ${DB_NAME}"
echo "DB_USERNAME : ${DB_USER}"
echo "DB_PASSWORD : ${DB_PASS}"
echo "FILE_SPESIFIK : ${DEST_SPECIFIC_MD}"
echo "FILE_MASTER   : ${MASTER_MD}"
echo "========================================"
