# 🤖 Rules & Guidelines for AI Agents (Docker Deploy System)

Dokumen ini berisi aturan wajib, standar arsitektur terintegrasi, dan konvensi pembuatan script deployment Docker, Database Multi-Engine, serta REST API Golang di lingkungan server ini. Setiap AI Agent yang melakukan modifikasi, penambahan generator, atau pemeliharaan sistem **WAJIB** mematuhi aturan ini.

---

## 📌 1. Arsitektur Struktur Direktori

| Komponen | Path di Server Host | Keterangan |
|---|---|---|
| **Deploy Root (Generator Scripts)** | `/home/yopa/Kuliah/Docker/deploy` | Master generator (`generate-*.sh`, `port.csv`, dll.) |
| **API Manager (Golang)** | `/home/yopa/Kuliah/Docker/deploy/api` | Backend REST API (`main.go`, `.env`, `whitelist.txt`) |
| **Database Engines Dir** | `/home/yopa/Kuliah/Docker/deploy/db/{engine}` | Konfigurasi database modular & `.env` kredensial |
| **Project Config Dir** | `/home/yopa/Documents/website_{username}_{framework}` | Berisi `docker-compose.yml`, `docker-config/nginx/`, `build.sh`, `README.md` |
| **App Source Code (FileBrowser)** | `/home/yopa/filebrowser/data/users/{username}/{framework}` | Lokasi source code / hasil `git clone` repository GitHub |
| **User Master Database File (FileBrowser)** | `/home/yopa/filebrowser/data/users/{username}/DATABASE.md` | Tabel akumulatif semua database yang dimiliki user (tidak pernah terhapus/tertindih) |
| **User Specific DB File (FileBrowser)** | `/home/yopa/filebrowser/data/users/{username}/DATABASE_{db_name}.md` | File kredensial spesifik per database |
| **Static WWW Source Code** | `/home/yopa/filebrowser/data/users/{username}/www` | Lokasi file HTML statis / web port WWW |
| **Port Tracking Database** | `/home/yopa/Kuliah/Docker/deploy/port.csv` | File CSV pencatat riwayat port |
| **Command Whitelist** | `/home/yopa/Kuliah/Docker/deploy/api/whitelist.txt` | Daftar awalan perintah yang diizinkan untuk Action 5 |

---

## 🚫 2. Aturan Wajib AI Agent (Strict Rules)

### 🔹 Rule 1: Multi-Database Support, Dedicated User & Manajemen Kredensial Markdown
Jika user membuat lebih dari 1 database (misal: database untuk toko, blog, ujian), sistem **DILARANG** menimpa (*overwrite*) kredensial lama:
1. **Prinsip 1 Database = 1 Dedicated DB User**: Setiap database yang dibuat **WAJIB** memiliki DB User tersendiri (misal: DB `user_indah_toko` -> User `user_indah_toko`) yang terisolasi dan hanya memiliki akses ke database itu saja.
2. **File Spesifik Per Database**: Setiap database baru dibuatkan file tersendiri:
   `/home/yopa/filebrowser/data/users/{username}/DATABASE_{db_name}.md`
3. **File Master Akumulatif (`DATABASE.md`)**: Setiap pembuatan database baru **wajib menambahkan baris baru (append)** ke tabel master `DATABASE.md` milik user tersebut, lengkap dengan nama database, user, password, dan timestamp.
4. Kredensial database wajib diberi izin baca FileBrowser (`chmod 666`).

### 🔹 Rule 2: Container Logs Monitoring API (`POST /api/container/logs`)
* API menyediakan pengambilan log runtime container dengan parameter `tail` (default `50`, min `1`, max `500`).
* Mendukung filter service opsional (`service: "app"` atau `service: "nginx"`).

### 🔹 Rule 3: Keamanan Kredensial Database (.env Support)
* **DILARANG KERAS** menuliskan password root/database secara *plain text / hardcoded* di dalam `docker-compose.yml` atau script shell `create-user-sql.sh`.
* Semua kredensial database engine wajib diletakkan di file `.env` lokal masing-masing (misal: `db/mariadb/.env`).
* Script database wajib membaca file `.env` tersebut secara dinamis.

### 🔹 Rule 4: Standar Universal Action 1–5 pada `build.sh`
Setiap file `build.sh` yang di-generate wajib memiliki pemetaan angka `1–5` yang konsisten agar mudah dikontrol oleh REST API:
* **`1` (Full Setup / Status Check)**: Install package dependencies / status check.
* **`2` (Install Dependencies)**: Package manager install (`composer install`, `npm install`, `pip install`).
* **`3` (Migration / Build)**: Database migration (`php spark migrate`, `php artisan migrate`) atau `npm run build`.
* **`4` (Database Seeder)**: Database seeder (`php spark db:seed`, `php artisan db:seed`, `prisma db seed`).
* **`5` (Custom Script)**: Menjalankan perintah bebas yang divalidasi oleh `whitelist.txt`.

### 🔹 Rule 5: Keamanan Eksekusi & Whitelist (`whitelist.txt`)
* Pada API Golang, setiap perintah kustom (Action 5: `extra_param`) **WAJIB** dicek terhadap file `api/whitelist.txt`.
* Karakter operator berantai seperti `;`, `&`, `|`, `` ` ``, `$`, `>`, `<` **WAJIB DIBLOKIR** untuk mencegah *Command Injection*.
* Prefix matching **WAJIB** menggunakan word boundary — prefix harus diikuti spasi atau end-of-string. Contoh: prefix `cat` tidak boleh cocok dengan `catapult`.
* **DILARANG** memasukkan entry whitelist yang terlalu generik dan berbahaya: `php`, `node`, `python`, `python3`, `go`, `cat`, `echo`, `grep`, `find`, `python -m`, `python -c`. Hanya entry spesifik yang aman (misal: `php artisan`, `node -v`, `python manage.py`).
* Input `username`, `framework`, `database_name` hanya boleh `[a-zA-Z0-9_]` — tanpa hyphen atau simbol lain.
* Jika perintah tidak cocok dengan salah satu baris di `whitelist.txt`, kembalikan status **HTTP 403 Forbidden**.

### 🔹 Rule 6: Integrasi GitHub Clone ke Folder FileBrowser
* Generator script harus mendukung **opsi URL Repository GitHub** (opsional).
* Target clone **HARUS** mengarah ke folder FileBrowser user (`/home/yopa/filebrowser/data/users/${USER_NAME}/${WEBSITE_NAME}`).

### 🔹 Rule 7: Alokasi Port Otomatis via `port.csv` (Atomic dengan `flock`)
* **DILARANG** melakukan hardcode port atau meminta input manual jika file `port.csv` sudah ada.
* Formula port:
  * `PORT` (App) = `LAST_PORT + 1`
  * `PORT_WWW` (Static) = `PORT + 1`
  * Default fallback: `10000`.
* **WAJIB** menggunakan `flock -x` (exclusive file lock) saat membaca DAN menulis ke `port.csv` agar tidak terjadi **race condition** pada request concurrent. Gunakan fungsi `allocate_port()` dengan pola:
  ```bash
  allocate_port() {
      (
          flock -x 200
          # baca LAST_PORT dari CSV
          # hitung PORT baru
          # tulis langsung ke CSV di dalam lock
          echo "$_PORT"
      ) 200>"${CSV_FILE}.lock"
  }
  PORT=$(allocate_port 10000)
  ```
* **DILARANG** memisahkan operasi baca port dan tulis port ke waktu yang berbeda (misal: baca di awal, tulis di akhir script). Kedua operasi harus dilakukan di dalam satu blok `flock`.

### 🔹 Rule 8: Penanganan User & Izin Akses File (Permissions)
* Pada `docker-compose.yml`, service `app` **HARUS** menyertakan:
  ```yaml
  user: "${HOST_UID}:${HOST_GID}"
  ```
* **SANGAT KRUSIAL**: Sebelum menjalankan `docker compose up -d`, script **WAJIB** membuat folder `WWW_DIR` dan `WWW_HTML_DIR` terlebih dahulu di host menggunakan `mkdir -p`.

### 🔹 Rule 9: Standar Docker Image per Framework / Service
* **Native PHP / HTML / CSS**: Gunakan image custom `nusantara-php84-native:1.0` (dari `Dockerfile-php`).
* **Laravel (Pure)**: Gunakan image custom `nusantara-php84-laravel:1.0` (dari `Dockerfile-laravel`).
* **CodeIgniter 4 & CI3**: Gunakan image custom `nusantara-php84-ci:1.0` (dari `Dockerfile-ci`).
* **Next.js**: Gunakan image custom `nusantara-node20-nextjs:1.0` (dari `Dockerfile-nextjs`) dengan Nginx reverse proxy ke `app:3000`.
* **Shared Network**: Koneksikan ke `mariadb-shared-net` (`net-phpmyadmin_shared`).

### 🔹 Rule 10: Kompatibilitas Non-Interaktif (API & Automation)
* Generator script (`generate-*.sh`) **harus bisa dipanggil dari API Golang** tanpa terminal interaktif.
* **DILARANG** menggunakan `read -p` tanpa guard `[ -t 0 ]` (cek stdin is terminal). Gunakan pola:
  ```bash
  if [ -z "$VAR" ] && [ -t 0 ]; then
      read -p "Masukkan input: " VAR
  fi
  ```
* **DILARANG** menggunakan `clear` tanpa guard `[ -t 1 ]` karena mengotori output API dengan ANSI escape codes.
* **DILARANG** menggunakan `sudo docker` dalam script yang dipanggil API. Gunakan `docker` langsung (pastikan user sudah masuk grup `docker`).

---

## 🛠️ 3. Checklist Sebelum Agent Menyelesaikan Task

- [ ] Multi-database credential tersimpan di `DATABASE_{db_name}.md` dan di-append ke `DATABASE.md`.
- [ ] Endpoint `/api/container/logs` mendukung limit `tail`.
- [ ] Kredensial database tersimpan di `.env` (bukan plain text di file script).
- [ ] Path source code di-mount dan di-clone ke `/home/yopa/filebrowser/data/users/{username}/{framework}`.
- [ ] Konfigurasi Docker & `build.sh` berada di `/home/yopa/Documents/website_{username}_{framework}`.
- [ ] `build.sh` lokal mengikuti standar pemetaan Action 1 s/d 5.
- [ ] Perintah Action 5 divalidasi dengan `api/whitelist.txt`.
- [ ] Folder target `WWW_DIR` & `WWW_HTML_DIR` sudah di-`mkdir` sebelum `docker compose up -d`.
- [ ] Format pencatatan `port.csv` sesuai skema `username,framework,port_app,port_www,created_at`.
- [ ] Alokasi port menggunakan `flock -x` untuk atomic read+write (tidak boleh terpisah).
- [ ] Script `generate-*.sh` kompatibel dengan panggilan non-interaktif dari API (tanpa `read -p` tanpa guard, tanpa `clear` tanpa guard, tanpa `sudo docker`).
