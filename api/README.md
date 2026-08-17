# 🚀 Deploy Manager API (Golang)

REST API Server berbasis Golang untuk mengontrol pembuatan container, eksekusi build/setup, alokasi port otomatis, dan manajemen lifecycle container Docker.

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

## 🛡️ 2. Sistem Whitelist Keamanan (`whitelist.txt`)

File [`api/whitelist.txt`](file:///home/yopa/Kuliah/Docker/deploy/api/whitelist.txt) berisi daftar awalan perintah (*command prefix*) yang **diizinkan** untuk dijalankan via Action `5` (Custom Command):

```text
composer
php artisan
php spark
php
git pull
git status
npm run build
npm install
```

### 🔒 Aturan Validasi Keamanan:
1. **Operator Chaining Ditolak**: Karakter seperti `;`, `&`, `|`, `` ` ``, `$`, `>`, `<` otomatis diblokir untuk mencegah injeksi perintah berantai.
2. **Hanya Perintah Terdaftar**: Jika perintah tidak diawali dengan teks di `whitelist.txt`, server merespons dengan **HTTP 403 Forbidden**.
3. **Melihat Whitelist Aktif**: `GET /api/whitelist`.

---

## ▶️ 3. Cara Menjalankan Server API

Masuk ke folder `api/` lalu jalankan:

```bash
cd /home/yopa/Kuliah/Docker/deploy/api
go run main.go
```

Atau compile menjadi binary:

```bash
go build -o deploy-api main.go
./deploy-api
```

---

## 📡 4. Daftar Endpoint & Contoh Penggunaan

### A. Eksekusi `build.sh` (`POST /api/build`)
Menjalankan script `build.sh` pada project target di `/home/yopa/Documents/website_{username}_{framework}/build.sh`.

```bash
# Contoh 1: Full Setup (Permissions + .env + Composer)
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "action": "1"
  }'

# Contoh 2: Run Database Seeder (Action 4)
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "action": "4",
    "extra_param": "UserSeeder"
  }'

# Contoh 3: Run Custom Command (Action 5 - Divalidasi oleh whitelist.txt)
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "action": "5",
    "extra_param": "php check_tables.php"
  }'
```

---

### B. Melihat Whitelist Perintah (`GET /api/whitelist`)
```bash
curl -X GET http://localhost:8080/api/whitelist
```

---

### C. Generate Project Baru (`POST /api/generate`)
Membuat project dan container baru secara otomatis (termasuk alokasi port dan git clone jika URL diisi).

```bash
curl -X POST http://localhost:8080/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "username": "budi",
    "framework": "laravel",
    "git_repo": "https://github.com/laravel/laravel.git"
  }'
```

---

### D. Kontrol Container (`POST /api/container`)
Mengontrol docker compose pada project (`restart`, `stop`, `start`, `down`, `ps`).

```bash
curl -X POST http://localhost:8080/api/container \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "action": "restart"
  }'
```

---

### E. List Website & Port (`GET /api/list`)
Membaca daftar semua website dan port yang aktif dari `port.csv`.

```bash
curl -X GET http://localhost:8080/api/list
```

---

### F. Health Check (`GET /api/health`)
```bash
curl -X GET http://localhost:8080/api/health
```
