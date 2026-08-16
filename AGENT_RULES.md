# 🤖 Rules & Guidelines for AI Agents (Docker Deploy System)

Dokumen ini berisi aturan wajib, standar arsitektur terintegrasi, dan konvensi pembuatan script deployment Docker untuk berbagai framework (Laravel, CodeIgniter 4, CodeIgniter 3, dll.) di lingkungan server ini. Setiap AI Agent yang melakukan modifikasi, penambahan generator, atau pemeliharaan sistem **WAJIB** mematuhi aturan ini.

---

## 📌 1. Arsitektur Struktur Direktori (FileBrowser Integration)

Sistem memisahkan antara **konfigurasi Docker** dan **Source Code aplikasi (FileBrowser)** agar siswa/user dapat mengelola file kodenya secara visual via FileBrowser Web UI:

| Komponen | Path di Server Host | Keterangan |
|---|---|---|
| **Deploy Root (Generator Scripts)** | `/home/yopa/Kuliah/Docker/deploy` | Lokasi master script (`generate-*.sh`, `port.csv`, dll.) |
| **Project Config Dir** | `/home/yopa/Documents/website_{username}_{framework}` | Berisi `docker-compose.yml`, `docker-config/nginx/`, `build.sh`, `README.md` |
| **App Source Code (FileBrowser)** | `/home/yopa/filebrowser/data/users/{username}/{framework}` | Lokasi source code / hasil `git clone` repository GitHub |
| **Static WWW Source Code** | `/home/yopa/filebrowser/data/users/{username}/www` | Lokasi file HTML statis / web port WWW |
| **Port Tracking Database** | `/home/yopa/Kuliah/Docker/deploy/port.csv` | File CSV pencatat riwayat port |

---

## 🚫 2. Aturan Wajib AI Agent (Strict Rules)

### 🔹 Rule 1: Integrasi GitHub Clone ke Folder FileBrowser
* Generator script harus mendukung **opsi URL Repository GitHub** (opsional):
  ```bash
  if [ -n "$GITHUB_REPO" ]; then
      git clone "$GITHUB_REPO" "$WWW_DIR"
  else
      mkdir -p "$WWW_DIR"
  fi
  ```
* Target clone **HARUS** mengarah ke folder FileBrowser user (`/home/yopa/filebrowser/data/users/${USER_NAME}/${WEBSITE_NAME}`).

---

### 🔹 Rule 2: Alokasi Port Otomatis via `port.csv`
* **DILARANG** melakukan hardcode port atau meminta input manual jika file `port.csv` sudah ada.
* Agent harus selalu mengekstrak port terbawah dari `port.csv`:
  ```bash
  LAST_PORT=$(awk -F',' 'NR>1 && $4 ~ /^[0-9]+$/ {print $4}' "$CSV_FILE" | tail -n 1)
  ```
* Formula port:
  * `PORT` (App) = `LAST_PORT + 1`
  * `PORT_WWW` (Static) = `PORT + 1`
  * Default fallback (jika `port.csv` kosong/baru): `10000`.
* Setelah alokasi berhasil, catat ke `port.csv` dengan format:
  `username,framework,port_app,port_www,created_at`

---

### 🔹 Rule 3: Penanganan User & Izin Akses File (Permissions)
* Pada `docker-compose.yml`, service `app` **HARUS** menyertakan:
  ```yaml
  user: "${HOST_UID}:${HOST_GID}"
  ```
  *(Hal ini memastikan proses aplikasi berjalan di bawah UID host user `1000`, bukan `root`).*
* **SANGAT KRUSIAL**: Sebelum menjalankan `docker compose up -d`, script **WAJIB** membuat folder `WWW_DIR` dan `WWW_HTML_DIR` terlebih dahulu di host menggunakan `mkdir -p`.
  * *Mengapa?* Jika folder belum ada saat Docker mounting volume, Docker Daemon akan membuatnya sebagai `root:root` yang mengunci izin file bagi user FileBrowser.
* **Pre-set Writable Folders**:
  * **CodeIgniter 4**: Pre-create `writable/cache`, `writable/logs`, `writable/session`, `writable/uploads`, `writable/debugbar` dan set `chmod -R 777`.
  * **Laravel**: Pre-create `storage/app`, `storage/framework/cache`, `storage/framework/sessions`, `storage/framework/views`, `storage/logs`, `bootstrap/cache` dan set `chmod -R 777`.

---

### 🔹 Rule 4: Generasi `build.sh` Lokal per Project (Dual Mode API & CLI)
* Setiap script `generate-*.sh` **WAJIB** menghasilkan file helper lokal bernama **`build.sh`** di dalam `/home/yopa/Documents/website_{user}_{framework}/build.sh`.
* Script `build.sh` lokal **HARUS kompatibel ganda**:
  1. **Interactive CLI Mode**: Memiliki prompt menu interaktif (`read -p`) jika dijalankan manual di terminal.
  2. **Non-Interactive API Mode**: Menerima argumen `$1` (pilihan action) dan `$2` (extra parameter) tanpa menggantung (*hang*) saat dipanggil oleh REST API / Golang executor via `exec.Command`.
* `build.sh` yang dihasilkan wajib diberi izin eksekusi (`chmod +x`).

---

### 🔹 Rule 5: Standar Docker Image & Network
* **CodeIgniter 4 & CI3**: Gunakan image custom `nusantara-php84-ci:1.0` (yang di-build dari `Dockerfile-ci`). Image ini wajib memiliki ekstensi `ext-intl`, `mysqli`, `pdo_mysql`, dan `composer` bawaan.
* **Laravel**: Gunakan image `nusantara-php84:1.0`.
* **Shared Network**: Semua container dikoneksikan ke external network `mariadb-shared-net` (`net-phpmyadmin_shared`) agar bisa mengakses MariaDB pusat.

---

## 🛠️ 3. Checklist Sebelum Agent Menyelesaikan Task

- [ ] Source code di-mount dan di-clone ke `/home/yopa/filebrowser/data/users/{username}/{framework}`.
- [ ] Konfigurasi Docker & `build.sh` berada di `/home/yopa/Documents/website_{username}_{framework}`.
- [ ] Folder target `WWW_DIR` & `WWW_HTML_DIR` sudah di-`mkdir` sebelum `docker compose up -d`.
- [ ] Format pencatatan `port.csv` sesuai skema `username,framework,port_app,port_www,created_at`.
- [ ] `docker-compose.yml` mencakup `user: "${HOST_UID}:${HOST_GID}"` dan network `mariadb-shared-net`.
- [ ] `build.sh` lokal berhasil dibuat di `PROJECT_DIR` dan mendukung argumen CLI/API (`$1`, `$2`).
