# 🚀 Deploy Manager API (Golang)

REST API Server berbasis Golang untuk mengontrol pembuatan container web (Laravel, CI4, CI3, Next.js, Native PHP), database multi-engine dengan dedicated user per database, eksekusi build/setup, alokasi port otomatis (atomic `flock`), pengambilan log container, dan manajemen lifecycle Docker.

---

## 🛠️ 1. Konfigurasi Environment (`.env`)

File konfigurasi berada di [`api/.env`](file:///home/yopa/Kuliah/Docker/deploy/api/.env):

```ini
PORT=8080
DOCUMENTS_BASE_DIR=/home/yopa/Documents
DEPLOY_BASE_DIR=/home/yopa/Kuliah/Docker/deploy
TIMEOUT_MINUTES=5
WHITELIST_FILE=whitelist.txt
```

---

## 🛡️ 2. Aturan Keamanan & Validasi Input

1. **Aturan Karakter Ilegal**:
   * Field `username`, `framework`, dan `database_name` **hanya mengizinkan** huruf, angka, dan underscore (`^[a-zA-Z0-9_]+$`).
   * Tanda strip/hyphen (`-`) dan simbol lainnya **ditolak** (`HTTP 400 Bad Request`) untuk mencegah SQL syntax error dan path traversal.

2. **Aturan Whitelist Perintah (Action 5)**:
   * Perintah kustom pada Action 5 wajib cocok dengan daftar awalan di [`api/whitelist.txt`](file:///home/yopa/Kuliah/Docker/deploy/api/whitelist.txt).
   * Prefix matching menggunakan **word boundary** (harus diikuti spasi atau end-of-string).
   * Perintah generik berbahaya (seperti `php -r`, `node -e`, `python -c`, `cat`, `echo`, `grep`, `find`) **diblokir**.
   * Karakter operator berantai (`;&|`$`<>`) **diblokir** (`HTTP 403 Forbidden`).

3. **Prinsip 1 Database = 1 Dedicated User**:
   * Setiap pembuatan database akan membuat **Dedicated DB User khusus** (misal DB `user_indah_toko` -> DB User `user_indah_toko`).
   * Kredensial tidak saling timpa dan setiap database memiliki isolasi hak akses penuh.

---

## 📡 3. Daftar Endpoint & Contoh Penggunaan

### A. Generate Project Web Baru (`POST /api/generate`)
Membuat project dan container web baru (+ auto-port atomic `flock` & optional Git clone).

* **Framework yang Didukung**:
  * `"php"` / `"native"` / `"html"` / `"nativephp"` ➡️ **Native PHP / HTML / CSS biasa** (sangat ringan).
  * `"laravel"` ➡️ **Laravel (PHP 8.4)**.
  * `"ci4"` ➡️ **CodeIgniter 4 (PHP 8.4)**.
  * `"ci3"` ➡️ **CodeIgniter 3 (PHP 8.4)**.
  * `"nextjs"` ➡️ **Next.js (Node.js 20)**.

```bash
# Contoh 1: Generate Native PHP / HTML / CSS
curl -X POST http://localhost:8080/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "php",
    "git_repo": ""
  }'

# Contoh 2: Generate Laravel dengan Git Clone
curl -X POST http://localhost:8080/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "laravel",
    "git_repo": "https://github.com/laravel/laravel.git"
  }'
```

---

### B. Mengambil Log Container (`POST /api/container/logs`)
Mengambil log runtime dari container Docker dengan batasan jumlah baris (`tail`: 1 - 500, default: 50), serta filter service opsional (`"app"`, `"nginx"`).

```bash
# Mengambil 20 baris log terakhir
curl -X POST http://localhost:8080/api/container/logs \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "php",
    "tail": 20
  }'
```

---

### C. Membuat Database & Dedicated User Baru (`POST /api/database/create`)
Membuat database dan dedicated user di MariaDB. Setiap database diisolasi dengan DB User khusus.

```bash
# 1. Membuat Database Utama (user_indah) & Dedicated User (user_indah)
curl -X POST http://localhost:8080/api/database/create \
  -H "Content-Type: application/json" \
  -d '{
    "engine": "mariadb",
    "username": "indah"
  }'

# 2. Membuat Database Tambahan (user_indah_toko) & Dedicated User (user_indah_toko)
curl -X POST http://localhost:8080/api/database/create \
  -H "Content-Type: application/json" \
  -d '{
    "engine": "mariadb",
    "username": "indah",
    "database_name": "toko"
  }'
```

* **Contoh JSON Response**:
```json
{
  "status": "success",
  "message": "Database user_indah_toko berhasil dibuat untuk engine mariadb",
  "data": {
    "engine": "mariadb",
    "database": "user_indah_toko",
    "db_user": "user_indah_toko",
    "owner": "indah",
    "host": "mariadb_container",
    "specific_credential_md": "/home/yopa/filebrowser/data/users/indah/DATABASE_user_indah_toko.md",
    "master_credential_md": "/home/yopa/filebrowser/data/users/indah/DATABASE.md"
  }
}
```

---

### D. Eksekusi `build.sh` (`POST /api/build`)
Menjalankan script `build.sh` pada project target di `/home/yopa/Documents/website_{username}_{framework}/build.sh`.

```bash
# Action standar: 1=Full Setup, 2=Install Deps, 3=Migrate/Build, 4=Seed, 5=Custom Command
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "php",
    "action": "1"
  }'

# Contoh Custom Command (Action 5)
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "laravel",
    "action": "5",
    "extra_param": "php artisan route:list"
  }'
```

---

### E. Kontrol Container (`POST /api/container`)
Mengontrol docker compose pada project (`restart`, `stop`, `start`, `down`, `ps`).

```bash
curl -X POST http://localhost:8080/api/container \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "php",
    "action": "restart"
  }'
```

---

### F. List Website & Port (`GET /api/list`)
Membaca daftar website yang telah terdaftar beserta port App & WWW dari `port.csv`.

```bash
curl -X GET http://localhost:8080/api/list
```

---

### G. Melihat Whitelist Perintah (`GET /api/whitelist`)
Melihat daftar awalan perintah yang diizinkan untuk Action 5.

```bash
curl -X GET http://localhost:8080/api/whitelist
```

---

### H. Health Check (`GET /api/health`)
Mengecek status kesehatan API server.

```bash
curl -X GET http://localhost:8080/api/health
```
