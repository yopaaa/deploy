# 🚀 Deploy Manager API (Golang)

REST API Server berbasis Golang untuk mengontrol pembuatan container web, database multi-engine, eksekusi build/setup, alokasi port otomatis, pengambilan log container, dan manajemen lifecycle Docker.

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

### A. Mengambil Log Container (`POST /api/container/logs`)
Mengambil log runtime dari container Docker dengan batasan jumlah baris (`tail`), serta filter service opsional (`"app"`, `"nginx"`).

```bash
# Contoh 1: Mengambil 20 baris log terakhir (semua service)
curl -X POST http://localhost:8080/api/container/logs \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "tail": 20
  }'

# Contoh 2: Mengambil 50 baris log khusus service aplikasi (app)
curl -X POST http://localhost:8080/api/container/logs \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "tail": 50,
    "service": "app"
  }'

# Contoh 3: Mengambil 100 baris log web server Nginx
curl -X POST http://localhost:8080/api/container/logs \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "tail": 100,
    "service": "nginx"
  }'
```

#### 📄 Format Response JSON:
```json
{
  "status": "success",
  "message": "Berhasil mengambil 20 baris log untuk website_indah_ci4",
  "output": "172.20.0.1 - - [17/Aug/2026:14:30:00 +0000] \"GET / HTTP/1.1\" 200 1520\n[17-Aug-2026 14:30:05] NOTICE: [pool www] child 7 started",
  "data": {
    "username": "indah",
    "framework": "ci4",
    "tail_lines": 20,
    "service": ""
  }
}
```

> 💡 **Ketentuan Parameter `tail`**:
> * Nilai default: `50` baris.
> * Minimal: `1` baris.
> * Maksimal: `500` baris (untuk mencegah beban memori server).

---

### B. Membuat Database & User Baru (`POST /api/database/create`)
Membuat database dan user otomatis di MariaDB (mendukung pembuatan multi-database untuk 1 user).

```bash
# Contoh 1: Membuat Database Default (user_indah)
curl -X POST http://localhost:8080/api/database/create \
  -H "Content-Type: application/json" \
  -d '{
    "engine": "mariadb",
    "username": "indah"
  }'

# Contoh 2: Membuat Database Tambahan / Spesifik (user_indah_toko)
curl -X POST http://localhost:8080/api/database/create \
  -H "Content-Type: application/json" \
  -d '{
    "engine": "mariadb",
    "username": "indah",
    "database_name": "toko"
  }'
```

---

### C. Eksekusi `build.sh` (`POST /api/build`)
Menjalankan script `build.sh` pada project target di `/home/yopa/Documents/website_{username}_{framework}/build.sh`.

```bash
# Full Setup (Permissions + .env + Composer/NPM)
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "action": "1"
  }'

# Run Database Seeder (Action 4)
curl -X POST http://localhost:8080/api/build \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "action": "4",
    "extra_param": "UserSeeder"
  }'

# Run Custom Command (Action 5 - Divalidasi oleh whitelist.txt)
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

### D. Generate Project Web Baru (`POST /api/generate`)
Membuat project dan container web baru (Laravel, CI4, CI3, Next.js) + auto-port & Git clone.

```bash
curl -X POST http://localhost:8080/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "username": "indah",
    "framework": "ci4",
    "git_repo": "https://github.com/user/ci4-project.git"
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
    "framework": "ci4",
    "action": "restart"
  }'
```

---

### F. List Website & Port (`GET /api/list`)
Membaca daftar semua website dan port yang aktif dari `port.csv`.

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
