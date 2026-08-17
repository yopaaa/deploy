# 🚀 Deploy Manager API (Golang)

REST API Server berbasis Golang untuk mengontrol pembuatan container web (Laravel, CI4, CI3, Next.js, Native PHP), database multi-engine, eksekusi build/setup, alokasi port otomatis, pengambilan log container, dan manajemen lifecycle Docker.

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

## 📡 2. Daftar Endpoint & Contoh Penggunaan

### A. Generate Project Web Baru (`POST /api/generate`)
Membuat project dan container web baru (+ auto-port & Git clone).

* **Framework yang Didukung**:
  * `"php"` / `"native"` / `"html"` ➡️ **Native PHP / HTML / CSS biasa** (sangat ringan).
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
Mengambil log runtime dari container Docker dengan batasan jumlah baris (`tail`), serta filter service opsional (`"app"`, `"nginx"`).

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

### C. Membuat Database & User Baru (`POST /api/database/create`)
Membuat database dan user otomatis di MariaDB (mendukung pembuatan multi-database untuk 1 user).

```bash
# Membuat Database Default (user_indah)
curl -X POST http://localhost:8080/api/database/create \
  -H "Content-Type: application/json" \
  -d '{
    "engine": "mariadb",
    "username": "indah"
  }'

# Membuat Database Spesifik (user_indah_toko)
curl -X POST http://localhost:8080/api/database/create \
  -H "Content-Type: application/json" \
  -d '{
    "engine": "mariadb",
    "username": "indah",
    "database_name": "toko"
  }'
```

---

### D. Eksekusi `build.sh` (`POST /api/build`)
Menjalankan script `build.sh` pada project target di `/home/yopa/Documents/website_{username}_{framework}/build.sh`.

```bash
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "php",
    "action": "1"
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
```bash
curl -X GET http://localhost:8080/api/list
```

---

### G. Melihat Whitelist Perintah (`GET /api/whitelist`)
```bash
curl -X GET http://localhost:8080/api/whitelist
```

---

### H. Health Check (`GET /api/health`)
```bash
curl -X GET http://localhost:8080/api/health
```
