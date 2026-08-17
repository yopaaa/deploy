# 🐛 Laporan Bug Review — Deploy Project

**Tanggal Review:** 2026-08-17  
**Scope:** Seluruh file di `/home/yopa/Kuliah/Docker/deploy/`

---

## 📊 Ringkasan

| Severity | Jumlah |
|---|---|
| 🔴 CRITICAL | 4 |
| 🟠 HIGH | 6 |
| 🟡 MEDIUM | 5 |
| 🔵 LOW | 4 |
| **Total** | **19** |

---

## 🔴 CRITICAL BUGS

---

### BUG-01: ~~Race Condition pada Alokasi Port (Semua Generator Scripts)~~ ✅ FIXED

**File yang terdampak:**
- `generate-laravel.sh` (baris 28-44, 368)
- `generate-ci4.sh` (baris 28-44, 365)
- `generate-ci3.sh` (baris 28-44, 329)
- `generate-nextjs.sh` (baris 28-44, 318)
- `generate-php.sh` (baris 28-44, 364)

**Deskripsi Detail:**

Script membaca port terakhir dari `port.csv` di awal eksekusi, menyimpannya di variabel memori, lalu baru menulis port baru ke CSV di **akhir** script (setelah docker compose up). Jarak waktu antara baca dan tulis bisa **puluhan detik**.

Jika 2 request API `/api/generate` dijalankan bersamaan (concurrent), keduanya akan membaca `LAST_PORT` yang sama dan menghasilkan port duplikat.

**Contoh Skenario Gagal:**

```
Waktu 0.0s: Request A membaca port.csv → LAST_PORT=10001 → PORT=10002
Waktu 0.1s: Request B membaca port.csv → LAST_PORT=10001 → PORT=10002 (DUPLIKAT!)
Waktu 3.0s: Request A menulis 10002,10003 ke port.csv
Waktu 5.0s: Request B menulis 10002,10003 ke port.csv (DUPLIKAT!)
Waktu 5.1s: Docker compose B CRASH → port 10002 already in use
```

**Kode Bermasalah (baris 33-38):**

```bash
LAST_PORT=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+$/ {print $4}' "$CSV_FILE" | tail -n 1)
if [ -n "$LAST_PORT" ]; then
    PORT=$((LAST_PORT + 1))
fi
```

**Solusi:**

Gunakan `flock` untuk file locking agar hanya satu proses bisa baca-tulis CSV pada satu waktu:

```bash
allocate_port() {
    (
        flock -x 200

        if [ ! -f "$CSV_FILE" ]; then
            echo "username,framework,port_app,port_www,created_at" > "$CSV_FILE"
        fi

        LAST_PORT=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+$/ {print $4}' "$CSV_FILE" | tail -n 1)
        if [ -n "$LAST_PORT" ]; then
            PORT=$((LAST_PORT + 1))
        else
            PORT=${1:-10000}
        fi
        PORT_WWW=$((PORT + 1))

        CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')
        echo "${USER_NAME},${WEBSITE_NAME},${PORT},${PORT_WWW},${CREATED_AT}" >> "$CSV_FILE"

        echo "$PORT"
    ) 200>"${CSV_FILE}.lock"
}

PORT=$(allocate_port 10000)
PORT_WWW=$((PORT + 1))
```

---

### BUG-02: ~~Script Generator Hang saat Dipanggil dari API (stdin blocking)~~ ✅ FIXED

**File yang terdampak:**
- Semua `generate-*.sh` (baris 23, 25, 42)
- `db/mariadb/create-user-sql.sh` (baris 67-68)

**Deskripsi Detail:**

Script menggunakan `read -p` untuk input tanpa mengecek apakah stdin adalah terminal interaktif (`[ -t 0 ]`).

Saat dipanggil dari API Golang, `main.go` baris 330-331 hanya mengirim 2 baris input:

```go
stdinPayload := fmt.Sprintf("%s\n%s\n", req.Username, req.GitRepo)
cmd.Stdin = strings.NewReader(stdinPayload)
```

Tapi script memiliki **3 titik read**:
1. Baris 23: `read -p "Masukkan username"` → membaca baris 1 dari stdin ✅
2. Baris 25: `read -p "Masukkan Repo GitHub"` → membaca baris 2 dari stdin ✅
3. Baris 42: `read -p "Masukkan port awal"` → **TIDAK ADA INPUT** ❌

Baris 42 hanya dieksekusi jika `port.csv` kosong. Jika ini terjadi:
- Di terminal: user bisa ketik manual
- Di API: `read` membaca **string kosong** → `PORT=""` → validasi baris 49 gagal → script exit

**Solusi:**

Ubah script agar menerima argumen CLI sebagai prioritas utama, fallback ke `read -p` hanya jika interaktif:

```bash
USER_NAME="${1:-}"
GITHUB_REPO="${2:-}"

if [ -z "$USER_NAME" ]; then
    if [ -t 0 ]; then
        read -p "Masukkan username: " USER_NAME
    else
        log_error "Username wajib diisi (argumen pertama)"
        exit 1
    fi
fi
```

Dan di `main.go`, ubah pemanggilan menjadi argumen:

```go
cmd := exec.CommandContext(ctx, "bash", scriptPath, req.Username, req.GitRepo)
```

---

### BUG-03: ~~SQL Syntax Error untuk Database Name dengan Hyphen~~ ✅ FIXED (ditolak di API)

**File:** `db/mariadb/create-user-sql.sh`  
**Baris:** 96, 99

**Deskripsi Detail:**

SQL statement tidak menggunakan backtick untuk identifier:

```sql
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
```

Regex validasi di API (`api/main.go` baris 129) mengizinkan hyphen:

```go
var validNameRegex = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
```

Jika user membuat database dengan nama `my-app`, maka `DB_NAME` menjadi `user_indah_my-app`. SQL yang dihasilkan:

```sql
CREATE DATABASE IF NOT EXISTS user_indah_my-app;
-- MariaDB Error: You have an error in your SQL syntax
```

MariaDB menginterpretasi `-app` sebagai **minus operator** diikuti identifier `app`.

**Solusi:**

Wrap semua SQL identifier dengan backtick:

```sql
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
```

---

### BUG-04: ~~Whitelist Prefix Matching Terlalu Loose — Command Injection Bypass~~ ✅ FIXED

**File:** `api/main.go`  
**Baris:** 167-169

**Deskripsi Detail:**

Whitelist validasi menggunakan `strings.HasPrefix`:

```go
if strings.HasPrefix(strings.ToLower(cmdTrimmed), strings.ToLower(allowedPrefix)) {
    return true, ""
}
```

Whitelist berisi entry pendek seperti `cat`, `echo`, `ls`, `php`, `node`, `go`, `python`. Karena hanya cek **prefix**, command berbahaya bisa lolos:

| Command | Prefix Match | Bahaya |
|---|---|---|
| `cat /etc/shadow` | `cat` ✅ | Baca file sensitif |
| `php -r "system('whoami');"` | `php` ✅ | Eksekusi arbitrary command |
| `node -e "require('child_process').execSync('rm -rf /')"` | `node` ✅ | Hapus seluruh filesystem |
| `python -c "import os; os.system('...')"` | `python` ✅ | Eksekusi arbitrary command |
| `echo password123 > /tmp/leak` | Blocked oleh `>` regex ✅ | Aman |
| `go run malicious.go` | `go run` ✅ | Eksekusi kode arbitrary |

Perhatikan: meskipun `dangerousCharRegex` memblokir `;`, `&`, `|`, `>`, `<`, `` ` ``, `$`, perintah seperti `php -r "..."` **tidak mengandung karakter tersebut** tapi tetap bisa mengeksekusi code arbitrary.

**Solusi:**

1. Tambahkan word boundary check setelah prefix match:

```go
if strings.HasPrefix(lowerCmd, lowerPrefix) {
    // Pastikan prefix diikuti spasi atau end-of-string
    if len(lowerCmd) == len(lowerPrefix) || lowerCmd[len(lowerPrefix)] == ' ' {
        return true, ""
    }
}
```

2. Hapus entry whitelist yang terlalu generik (`cat`, `echo`, `ls`, `php`, `node`, `go`, `python`) dan hanya izinkan perintah spesifik yang aman.

3. Tambahkan blacklist argumen berbahaya (`-r`, `-e`, `-c`, `--eval`, `--exec`).

---

## 🟠 HIGH BUGS

---

### BUG-05: Password Root MariaDB Terekspos via Process List

**File:** `db/mariadb/create-user-sql.sh`  
**Baris:** 95

**Deskripsi Detail:**

```bash
sudo docker exec -i ${CONTAINER_NAME} mariadb -u root -p${ROOT_PW} <<EOF
```

Password root dikirim sebagai command-line argument. Semua user di server bisa melihatnya dengan `ps aux`:

```
root  12345  ... mariadb -u root -pbmgsTug8WxNKmUSOglUMQrYt27OgQ0Q7e2P
```

MariaDB sendiri mengeluarkan warning: `Using a password on the command line interface can be insecure.`

**Solusi:**

Gunakan environment variable `MYSQL_PWD`:

```bash
sudo docker exec -i -e MYSQL_PWD="${ROOT_PW}" ${CONTAINER_NAME} mariadb -u root <<EOF
```

---

### BUG-06: Git Clone Gagal jika Folder Sudah Ada

**File:** Semua `generate-*.sh`  
**Baris:** 83-90

**Deskripsi Detail:**

```bash
git clone "$GITHUB_REPO" "$WWW_DIR"
```

`git clone` gagal jika folder target sudah ada dan tidak kosong:

```
fatal: destination path '/home/yopa/filebrowser/data/users/indah/laravel' already exists and is not an empty directory.
```

Skenario ini terjadi jika:
1. User menjalankan generate 2 kali untuk username + framework yang sama
2. Run sebelumnya gagal di tengah jalan tapi folder sudah terbuat
3. User sudah punya file di folder tersebut sebelum generate

Script exit dengan error dan project tidak dibuat, tapi **tidak ada pesan error yang jelas** ke user.

**Solusi:**

```bash
if [ -n "$GITHUB_REPO" ]; then
    if [ -d "$WWW_DIR/.git" ]; then
        log_info "Repository sudah ada, melakukan git pull..."
        cd "$WWW_DIR" && git pull && cd -
    elif [ -d "$WWW_DIR" ] && [ "$(ls -A "$WWW_DIR" 2>/dev/null)" ]; then
        log_error "Folder $WWW_DIR sudah ada dan tidak kosong."
        log_error "Hapus folder tersebut atau jalankan tanpa git_repo."
        exit 1
    else
        mkdir -p "$(dirname "$WWW_DIR")"
        git clone "$GITHUB_REPO" "$WWW_DIR"
        if [ $? -ne 0 ]; then
            log_error "Gagal me-clone repository GitHub."
            exit 1
        fi
    fi
fi
```

---

### BUG-07: handleContainer Tidak Memvalidasi Username dan Framework

**File:** `api/main.go`  
**Baris:** 458-514

**Deskripsi Detail:**

Endpoint `POST /api/container` (restart/stop/start/down/ps) **tidak** memvalidasi `req.Username` dan `req.Framework` dengan `validNameRegex`.

Bandingkan:
- `handleBuild` baris 205: **ada validasi** ✅
- `handleContainerLogs` baris 530: **ada validasi** ✅
- `handleContainer` baris 458-514: **TIDAK ADA validasi** ❌

Input langsung digunakan untuk path construction:

```go
projectFolder := fmt.Sprintf("website_%s_%s", req.Username, req.Framework)
projectDir := filepath.Join(cfg.DocumentsBaseDir, projectFolder)
```

Jika `req.Username` berisi `../../../etc`, path menjadi:

```
/home/yopa/Documents/website_../../../etc_laravel
```

`filepath.Join` akan resolve menjadi `/etc_laravel`. Meskipun ini kemungkinan gagal di `os.Stat`, ini tetap merupakan **missing validation** yang inkonsisten dan berbahaya.

**Solusi:**

Tambahkan setelah JSON decode (setelah baris 469):

```go
if !validNameRegex.MatchString(req.Username) || !validNameRegex.MatchString(req.Framework) {
    w.WriteHeader(http.StatusBadRequest)
    json.NewEncoder(w).Encode(ApiResponse{
        Status:  "error",
        Message: "Username atau Framework mengandung karakter ilegal",
    })
    return
}
```

---

### BUG-08: Next.js Container Tidak Akan Auto-Update Dependencies

**File:** `generate-nextjs.sh`  
**Baris:** 112

**Deskripsi Detail:**

Docker compose command:

```yaml
command: sh -c "if [ ! -d node_modules ] && [ -f package.json ]; then npm install; fi && npm run dev"
```

Logika: `npm install` hanya dijalankan jika `node_modules` **tidak ada**. Setelah pertama kali jalan dan `node_modules` terbuat, perintah ini **tidak pernah** menjalankan `npm install` lagi, meskipun user menambah package baru ke `package.json`.

**Dampak:** User menambah `axios` ke `package.json` → restart container → Next.js crash:
```
Module not found: Can't resolve 'axios'
```

**Solusi:**

Opsi A — Selalu install (lebih aman tapi lebih lambat):
```yaml
command: sh -c "if [ -f package.json ]; then npm install; fi && npm run dev"
```

Opsi B — Hapus auto-install, biarkan manual via build.sh:
```yaml
command: sh -c "npm run dev"
```

---

### BUG-09: `sudo docker compose` Gagal via API (Non-Interactive sudo)

**File:** Semua `generate-*.sh`  
**Baris:** 379 (laravel), 376 (ci4), 340 (ci3), 329 (nextjs), 375 (php)

**Deskripsi Detail:**

```bash
sudo docker compose up -d
```

Saat API Golang menjalankan script via `exec.Command`, proses berjalan **tanpa terminal**. `sudo` tidak bisa meminta password karena tidak ada TTY. Jika user `yopa` memerlukan password untuk sudo:

```
sudo: a terminal is required to read the password
```

Script gagal dan exit code non-zero dikembalikan ke API.

**Solusi:**

Tambahkan user ke grup `docker` agar tidak perlu `sudo`:

```bash
sudo usermod -aG docker yopa
# Logout dan login kembali
```

Lalu ubah semua script:
```bash
# Dari:
sudo docker compose up -d

# Menjadi:
docker compose up -d
```

---

### BUG-10: ~~`clear` Command Mengotori Output API~~ ✅ FIXED

**File:** Semua `generate-*.sh`  
**Baris:** 16

**Deskripsi Detail:**

```bash
clear
```

Perintah `clear` mengirim **ANSI escape sequences** (seperti `\033[H\033[2J`) ke stdout. Saat script dijalankan dari API, `cmd.CombinedOutput()` menangkap escape sequences ini dan memasukkannya ke JSON response.

Hasilnya, field `output` di JSON response API mengandung karakter tidak terlihat yang bisa merusak parsing di client.

**Solusi:**

Hanya jalankan `clear` jika terminal interaktif:

```bash
[ -t 1 ] && clear
```

---

## 🟡 MEDIUM BUGS

---

### BUG-11: Index Numbering Salah di DATABASE.md Master Table

**File:** `db/mariadb/create-user-sql.sh`  
**Baris:** 157-161

**Deskripsi Detail:**

```bash
COUNT=$(grep -c "^|" "$MASTER_MD")
INDEX=$((COUNT - 1))
if [ "$INDEX" -lt 1 ]; then INDEX=1; fi
```

`grep -c "^|"` menghitung **semua** baris yang dimulai dengan `|`:
- Baris header: `| No | DB Name | ...` → dihitung
- Baris separator: `|---|---|...` → dihitung
- Baris data: `| 1 | user_indah | ...` → dihitung

Saat database pertama dibuat, file `DATABASE.md` berisi:
```
| No | DB Name | Host | ...     ← baris 1 (|)
|---|---|---|...                  ← baris 2 (|)
| 1 | `user_indah` | ...        ← baris 3 (|)
```

Saat database kedua dibuat:
- `COUNT = 3` (3 baris dimulai `|`)
- `INDEX = 3 - 1 = 2` ✅ (kebetulan benar)

Saat database ketiga dibuat:
- `COUNT = 4`
- `INDEX = 4 - 1 = 3` ✅ (masih benar)

Sebenarnya **ini bekerja** karena baris header + separator = 2, dikurangi 1 = 1, lalu setiap data menambah 1. Tapi kalau format file berubah (misal ada baris `|` tambahan), indexing akan salah.

**Solusi yang lebih robust:**

```bash
# Hitung hanya baris data (yang mengandung backtick setelah pipe)
DATA_COUNT=$(grep -c "| \`" "$MASTER_MD" 2>/dev/null || echo "0")
INDEX=$((DATA_COUNT + 1))
```

---

### BUG-12: REVOKE ALL Menghapus Privilege Database Lama

**File:** `db/mariadb/create-user-sql.sh`  
**Baris:** 98

**Deskripsi Detail:**

```sql
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
```

**INI BUG PALING BERBAHAYA.** Skenario:

1. User `indah` membuat database pertama → `user_indah`
   - GRANT ALL ON `user_indah`.* → indah bisa akses `user_indah` ✅

2. User `indah` membuat database kedua → `user_indah_toko`
   - **REVOKE ALL** → hapus SEMUA privilege indah, termasuk akses ke `user_indah` ❌
   - GRANT ALL ON `user_indah_toko`.* → indah hanya bisa akses `user_indah_toko`
   - **Akses ke `user_indah` HILANG!** ❌❌❌

3. Aplikasi Laravel indah yang pakai database `user_indah` langsung **CRASH**:
   ```
   SQLSTATE[HY000]: Access denied for user 'indah'@'%' to database 'user_indah'
   ```

**Solusi:**

Hapus baris `REVOKE ALL` dan hanya lakukan `GRANT` tambahan:

```sql
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
```

---

### BUG-13: Password di Credential File Tidak Sesuai dengan Password Aktual

**File:** `db/mariadb/create-user-sql.sh`  
**Baris:** 89, 97

**Deskripsi Detail:**

Setiap kali script dijalankan, password baru di-generate:

```bash
DB_PASS=$(generate_password)    # Baris 89: Password random baru
```

Lalu SQL:
```sql
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
```

`CREATE USER IF NOT EXISTS` **tidak mengubah password** jika user sudah ada. Artinya:

1. Run pertama: password = `abc123` → user dibuat dengan password `abc123` → `DATABASE_user_indah.md` berisi `abc123` ✅
2. Run kedua: password = `xyz789` → `IF NOT EXISTS` → user **tidak diubah**, password tetap `abc123` → `DATABASE_user_indah_toko.md` berisi `xyz789` ❌

File credential kedua menunjukkan password `xyz789` tapi password sebenarnya masih `abc123`. User **tidak bisa login** dengan password di file.

**Solusi:**

Jika user sudah ada, update password-nya juga:

```sql
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
```

Atau alternatif: cek apakah user ada dulu, kalau sudah ada gunakan password yang sama dari credential file sebelumnya.

---

### BUG-14: CI3 build.sh Tidak Mengikuti Standar Action 1-5

**File:** `generate-ci3.sh`  
**Baris:** 228-259

**Deskripsi Detail:**

CI3 `build.sh` hanya memiliki 3 action:
- Action 1-2: `composer install`
- Action 3: custom command

Bandingkan dengan framework lain yang memiliki 5 action:
- Action 1: Full Setup
- Action 2: Package Install
- Action 3: Migration
- Action 4: Seeder
- Action 5: Custom Command

Saat API memanggil `build.sh 4` (seeder) atau `build.sh 5` (custom), CI3 masuk ke case `*` dan exit error. API Golang di `handleBuild` **tidak memvalidasi** action number berdasarkan framework — semua framework dianggap mendukung 1-5.

**Solusi:**

Ubah CI3 build.sh agar konsisten dengan standar 1-5:

```bash
case $CHOICE in
    1|2)
        echo "[INFO] Running composer install..."
        docker exec "${CONTAINER_NAME}" composer install
        ;;
    3)
        echo "[INFO] CI3 tidak memiliki migration CLI bawaan."
        echo "[INFO] Silakan jalankan migration manual via custom command."
        ;;
    4)
        echo "[INFO] CI3 tidak memiliki seeder CLI bawaan."
        echo "[INFO] Silakan jalankan seeder manual via custom command."
        ;;
    5)
        CUSTOM_CMD="$EXTRA_PARAM"
        if [ -z "$CUSTOM_CMD" ] && [ -t 0 ]; then
            read -p "Masukkan perintah: " CUSTOM_CMD
        fi
        if [ -n "$CUSTOM_CMD" ]; then
            docker exec "${CONTAINER_NAME}" $CUSTOM_CMD
        else
            echo "[ERROR] Perintah tidak boleh kosong."
            exit 1
        fi
        ;;
esac
```

---

### BUG-15: MariaDB docker-compose.yml Double-Loading Environment Variables

**File:** `db/mariadb/docker-compose.yml`  
**Baris:** 6-12

**Deskripsi Detail:**

```yaml
env_file:
  - .env
environment:
  MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
  MARIADB_DATABASE: ${MARIADB_DEFAULT_DATABASE}
  MARIADB_USER: ${MARIADB_DEFAULT_USER}
  MARIADB_PASSWORD: ${MARIADB_DEFAULT_PASSWORD}
```

Dua mekanisme berbeda digunakan bersamaan:

1. `env_file: .env` → Docker Compose membaca `.env` dan memasukkan semua variabel ke container sebagai environment variables.

2. `environment:` → Docker Compose melakukan **variable substitution** dari host shell environment (bukan dari `.env` file). Jadi `${MARIADB_ROOT_PASSWORD}` di-resolve dari shell environment, bukan dari `.env`.

Masalah: Variabel di `.env` bernama `MARIADB_ROOT_PASSWORD`, tapi MariaDB image membutuhkan `MARIADB_ROOT_PASSWORD`. Karena `env_file` sudah memasukkan variabel dengan nama yang benar, blok `environment:` seharusnya tidak perlu.

Tapi blok `environment:` juga melakukan **rename** variabel (misal `MARIADB_DEFAULT_DATABASE` → `MARIADB_DATABASE`). Jika `MARIADB_DEFAULT_DATABASE` tidak ada di host shell, nilainya menjadi kosong dan **menimpa** nilai dari `env_file`.

**Solusi:**

Opsi A — Rename variabel di `.env` agar sesuai langsung dengan yang dibutuhkan MariaDB:

```env
MARIADB_CONTAINER_NAME=mariadb_container
MARIADB_ROOT_PASSWORD=bmgsTug8WxNKmUSOglUMQrYt27OgQ0Q7e2P
MARIADB_DATABASE=db1
MARIADB_USER=3b78a2924629fc648
MARIADB_PASSWORD=ba644886b83629f3fbfffd1eb460f360a239f50cf8361d85a288d73088fb7fc8
```

```yaml
services:
  db:
    image: mariadb:10.8
    container_name: ${MARIADB_CONTAINER_NAME:-mariadb_container}
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data/mariadb:/var/lib/mysql
    networks:
      - shared-phpmyadmin
```

---

## 🔵 LOW BUGS

---

### BUG-16: Dockerfile-nextjs Tidak Digunakan

**File:** `Dockerfile-nextjs`

**Deskripsi:**

`Dockerfile-nextjs` ada di repository tapi `generate-nextjs.sh` menggunakan `image: node:20-alpine` secara langsung di docker-compose.yml (baris 107). Dockerfile ini tidak pernah di-build atau dipakai oleh script manapun.

**Solusi:**

Hapus file atau ubah `generate-nextjs.sh` agar menggunakan custom image.

---

### BUG-17: API Health Endpoint Tidak Validasi HTTP Method

**File:** `api/main.go`  
**Baris:** 695-706

**Deskripsi:**

`handleHealth` tidak mengecek method HTTP. POST, DELETE, PUT semua bisa mengakses health check. Tidak konsisten dengan endpoint lain yang semuanya mengecek method.

**Solusi:**

```go
func handleHealth(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
        return
    }
    // ... existing code
}
```

---

### BUG-18: API list Response Mengembalikan null Bukan Array Kosong

**File:** `api/main.go`  
**Baris:** 631

**Deskripsi:**

```go
var list []WebItem
```

Jika `port.csv` hanya berisi header tanpa data, `list` tetap `nil` karena tidak pernah di-append. Di JSON, `nil` slice diencoding menjadi `"data": null` bukan `"data": []`.

Client yang mengecek `response.data.length` akan crash karena `null.length` adalah error di JavaScript.

**Solusi:**

```go
list := make([]WebItem, 0)
```

---

### BUG-19: loadEnv Tidak Handle Quoted Values Edge Cases

**File:** `api/main.go`  
**Baris:** 48-49

**Deskripsi:**

```go
val = strings.Trim(val, `"'`)
```

`strings.Trim` menghapus semua karakter `"` dan `'` dari kedua ujung. Ini bermasalah untuk value yang mengandung quote di dalamnya:

- `VALUE="hello"` → `hello` ✅
- `VALUE="can't stop"` → `can't stop` → `can` (trimmed `'` di akhir juga) ❌

Untuk `.env` file sederhana ini kemungkinan tidak masalah, tapi perlu dicatat limitasinya.

**Solusi:**

Hanya strip matching pairs:

```go
if (strings.HasPrefix(val, `"`) && strings.HasSuffix(val, `"`)) ||
   (strings.HasPrefix(val, `'`) && strings.HasSuffix(val, `'`)) {
    val = val[1 : len(val)-1]
}
```

---

## 📋 Prioritas Perbaikan

### Fase 1: Harus Diperbaiki Segera (Sebelum Deploy)

| No | Bug | Alasan |
|---|---|---|
| 1 | BUG-12 | REVOKE ALL hapus privilege database lama — paling berbahaya |
| 2 | BUG-13 | Password mismatch di credential file |
| 3 | BUG-01 | Race condition port allocation — data corrupt |
| 4 | BUG-07 | Missing validation di handleContainer — path traversal |
| 5 | BUG-04 | Whitelist bypass — command injection |
| 6 | BUG-09 | sudo gagal dari API — semua generate crash |

### Fase 2: Harus Diperbaiki Sebelum Production

| No | Bug | Alasan |
|---|---|---|
| 7 | BUG-02 | stdin blocking — API hang |
| 8 | BUG-03 | SQL syntax error untuk hyphen |
| 9 | BUG-05 | Password visible di ps aux |
| 10 | BUG-10 | clear command di output API |
| 11 | BUG-14 | CI3 action mismatch |
| 12 | BUG-15 | Double env loading |

### Fase 3: Nice to Have

| No | Bug | Alasan |
|---|---|---|
| 13 | BUG-06 | Git clone folder exists |
| 14 | BUG-08 | node_modules stale |
| 15 | BUG-11 | Index numbering |
| 16-19 | BUG-16 s/d 19 | Minor improvements |

---

*Laporan ini di-generate oleh Antigravity AI Code Auditor pada 2026-08-17.*
