# 🤖 Rules & Guidelines for AI Agents (Docker Deploy System)

Dokumen ini berisi aturan wajib, standar arsitektur terintegrasi, dan konvensi pembuatan script deployment Docker serta REST API Golang di lingkungan server ini. Setiap AI Agent yang melakukan modifikasi, penambahan generator, atau pemeliharaan sistem **WAJIB** mematuhi aturan ini.

---

## 📌 1. Arsitektur Struktur Direktori (FileBrowser & API Integration)

| Komponen | Path di Server Host | Keterangan |
|---|---|---|
| **Deploy Root (Generator Scripts)** | `/home/yopa/Kuliah/Docker/deploy` | Master generator (`generate-*.sh`, `port.csv`, dll.) |
| **API Manager (Golang)** | `/home/yopa/Kuliah/Docker/deploy/api` | Backend REST API (`main.go`, `.env`, `whitelist.txt`) |
| **Project Config Dir** | `/home/yopa/Documents/website_{username}_{framework}` | Berisi `docker-compose.yml`, `docker-config/nginx/`, `build.sh`, `README.md` |
| **App Source Code (FileBrowser)** | `/home/yopa/filebrowser/data/users/{username}/{framework}` | Lokasi source code / hasil `git clone` repository GitHub |
| **Static WWW Source Code** | `/home/yopa/filebrowser/data/users/{username}/www` | Lokasi file HTML statis / web port WWW |
| **Port Tracking Database** | `/home/yopa/Kuliah/Docker/deploy/port.csv` | File CSV pencatat riwayat port |
| **Command Whitelist** | `/home/yopa/Kuliah/Docker/deploy/api/whitelist.txt` | Daftar awalan perintah yang diizinkan untuk Action 5 |

---

## 🚫 2. Aturan Wajib AI Agent (Strict Rules)

### 🔹 Rule 1: Standar Universal Action 1–5 pada `build.sh`
Setiap file `build.sh` yang di-generate wajib memiliki pemetaan angka `1–5` yang konsisten agar mudah dikontrol oleh REST API:
* **`1` (Full Setup)**: Install package dependencies + inisialisasi environment/build.
* **`2` (Install Dependencies)**: Package manager install (`composer install`, `npm install`, `pip install`).
* **`3` (Migration / Build)**: Database migration (`php spark migrate`, `php artisan migrate`) atau `npm run build`.
* **`4` (Database Seeder)**: Database seeder (`php spark db:seed`, `php artisan db:seed`, `prisma db seed`).
* **`5` (Custom Script)**: Menjalankan perintah bebas yang divalidasi oleh `whitelist.txt`.

### 🔹 Rule 2: Keamanan Eksekusi & Whitelist (`whitelist.txt`)
* Pada API Golang, setiap perintah kustom (Action 5: `extra_param`) **WAJIB** dicek terhadap file `api/whitelist.txt`.
* Karakter operator berantai seperti `;`, `&`, `|`, `` ` ``, `$`, `>`, `<` **WAJIB DIBLOKIR** untuk mencegah *Command Injection*.
* Jika perintah tidak cocok dengan salah satu baris di `whitelist.txt`, kembalikan status **HTTP 403 Forbidden**.

### 🔹 Rule 3: Integrasi GitHub Clone ke Folder FileBrowser
* Generator script harus mendukung **opsi URL Repository GitHub** (opsional):
  ```bash
  if [ -n "$GITHUB_REPO" ]; then
      git clone "$GITHUB_REPO" "$WWW_DIR"
  else
      mkdir -p "$WWW_DIR"
  fi
  ```
* Target clone **HARUS** mengarah ke folder FileBrowser user (`/home/yopa/filebrowser/data/users/${USER_NAME}/${WEBSITE_NAME}`).

### 🔹 Rule 4: Alokasi Port Otomatis via `port.csv`
* **DILARANG** melakukan hardcode port atau meminta input manual jika file `port.csv` sudah ada.
* Agent harus selalu mengekstrak port terbawah dari `port.csv`:
  ```bash
  LAST_PORT=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+$/ {print $4}' "$CSV_FILE" | tail -n 1)
  ```
* Formula port:
  * `PORT` (App) = `LAST_PORT + 1`
  * `PORT_WWW` (Static) = `PORT + 1`
  * Default fallback (jika `port.csv` kosong/baru): `10000`.
* Catat ke `port.csv` dengan format: `username,framework,port_app,port_www,created_at`

### 🔹 Rule 5: Penanganan User & Izin Akses File (Permissions)
* Pada `docker-compose.yml`, service `app` **HARUS** menyertakan:
  ```yaml
  user: "${HOST_UID}:${HOST_GID}"
  ```
* **SANGAT KRUSIAL**: Sebelum menjalankan `docker compose up -d`, script **WAJIB** membuat folder `WWW_DIR` dan `WWW_HTML_DIR` terlebih dahulu di host menggunakan `mkdir -p`.
* **Pre-set Writable Folders**:
  * **CodeIgniter 4**: Pre-create `writable/cache`, `writable/logs`, `writable/session`, `writable/uploads`, `writable/debugbar` dan set `chmod -R 777`.
  * **Laravel**: Pre-create `storage/app`, `storage/framework/cache`, `storage/framework/sessions`, `storage/framework/views`, `storage/logs`, `bootstrap/cache` dan set `chmod -R 777`.

### 🔹 Rule 6: Standar Docker Image per Framework
* **Laravel (Pure)**: Gunakan image custom `nusantara-php84-laravel:1.0` (dari `Dockerfile-laravel`).
* **CodeIgniter 4 & CI3**: Gunakan image custom `nusantara-php84-ci:1.0` (dari `Dockerfile-ci`).
* **Next.js**: Gunakan image `node:20-alpine` (dari `Dockerfile-nextjs`) dengan Nginx reverse proxy ke `app:3000`.
* **Shared Network**: Koneksikan ke `mariadb-shared-net` (`net-phpmyadmin_shared`).

---

## 🛠️ 3. Checklist Sebelum Agent Menyelesaikan Task

- [ ] Path source code di-mount dan di-clone ke `/home/yopa/filebrowser/data/users/{username}/{framework}`.
- [ ] Konfigurasi Docker & `build.sh` berada di `/home/yopa/Documents/website_{username}_{framework}`.
- [ ] `build.sh` lokal mengikuti standar pemetaan Action 1 s/d 5.
- [ ] Perintah Action 5 divalidasi dengan `api/whitelist.txt`.
- [ ] Folder target `WWW_DIR` & `WWW_HTML_DIR` sudah di-`mkdir` sebelum `docker compose up -d`.
- [ ] Format pencatatan `port.csv` sesuai skema `username,framework,port_app,port_www,created_at`.
