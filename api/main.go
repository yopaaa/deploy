package main

import (
	"bufio"
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Config menampung nilai konfigurasi dari environment
type Config struct {
	Port             string
	DocumentsBaseDir string
	DeployBaseDir    string
	TimeoutMinutes   int
	WhitelistFile    string
}

var cfg Config

// LoadEnv memuat file .env ke environment variables secara native
func loadEnv(envPath string) {
	file, err := os.Open(envPath)
	if err != nil {
		return
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			val = strings.Trim(val, `"'`)
			if os.Getenv(key) == "" {
				os.Setenv(key, val)
			}
		}
	}
}

func getEnv(key, defaultVal string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultVal
}

func initConfig() {
	loadEnv(".env")
	loadEnv(filepath.Join("api", ".env"))

	port := getEnv("PORT", "8080")
	if !strings.HasPrefix(port, ":") {
		port = ":" + port
	}

	timeoutStr := getEnv("TIMEOUT_MINUTES", "5")
	timeoutInt, err := strconv.Atoi(timeoutStr)
	if err != nil {
		timeoutInt = 5
	}

	cfg = Config{
		Port:             port,
		DocumentsBaseDir: getEnv("DOCUMENTS_BASE_DIR", "/home/yopa/Documents"),
		DeployBaseDir:    getEnv("DEPLOY_BASE_DIR", "/home/yopa/Kuliah/Docker/deploy"),
		TimeoutMinutes:   timeoutInt,
		WhitelistFile:    getEnv("WHITELIST_FILE", "whitelist.txt"),
	}
}

// Request Data
type BuildRequest struct {
	Username   string `json:"username"`    // Contoh: "indah"
	Framework  string `json:"framework"`   // Contoh: "ci4", "ci3", "laravel", "nextjs", "php"
	Action     string `json:"action"`      // Contoh: "1" (Full Setup), "2" (Package Install), "3" (Build/Migrate), "4" (Seed), "5" (Custom)
	ExtraParam string `json:"extra_param"` // Contoh: "UserSeeder" atau "npm run lint" (opsional)
}

type GenerateRequest struct {
	Username  string `json:"username"`
	Framework string `json:"framework"` // "laravel", "ci4", "ci3", "nextjs", "php"
	GitRepo   string `json:"git_repo"`
}

type ContainerActionRequest struct {
	Username  string `json:"username"`
	Framework string `json:"framework"`
	Action    string `json:"action"` // "restart", "stop", "start", "down", "ps"
}

type ContainerLogsRequest struct {
	Username  string `json:"username"`          // "indah"
	Framework string `json:"framework"`         // "ci4", "laravel", "nextjs", "php"
	Tail      int    `json:"tail,omitempty"`    // Batasan baris log (contoh: 20, 50, 100, max: 500, default: 50)
	Service   string `json:"service,omitempty"` // Opsional: "app", "nginx", atau kosong untuk semua service
}

type DatabaseCreateRequest struct {
	Engine       string `json:"engine"`        // "mariadb" (default)
	Username     string `json:"username"`      // "indah"
	DatabaseName string `json:"database_name"` // opsional: "toko", "blog"
}

// Response Data
type ApiResponse struct {
	Status  string      `json:"status"`
	Message string      `json:"message"`
	Output  string      `json:"output,omitempty"`
	Data    interface{} `json:"data,omitempty"`
}

var validNameRegex = regexp.MustCompile(`^[a-zA-Z0-9_]+$`)
var dangerousCharRegex = regexp.MustCompile(`[;&|` + "`" + `$<>]`)

// Memeriksa apakah perintah custom diizinkan berdasarkan whitelist.txt
func isCommandAllowed(command string) (bool, string) {
	cmdTrimmed := strings.TrimSpace(command)
	if cmdTrimmed == "" {
		return false, "Perintah tidak boleh kosong"
	}

	// Blokir karakter chaining berbahaya (; && || | ` $( > <)
	if dangerousCharRegex.MatchString(cmdTrimmed) {
		return false, "Perintah mengandung karakter operator berbahaya (; & | ` $ < >)"
	}

	whitelistPath := cfg.WhitelistFile
	if !filepath.IsAbs(whitelistPath) {
		if _, err := os.Stat(whitelistPath); os.IsNotExist(err) {
			whitelistPath = filepath.Join("api", cfg.WhitelistFile)
			if _, err := os.Stat(whitelistPath); os.IsNotExist(err) {
				whitelistPath = filepath.Join(cfg.DeployBaseDir, "api", cfg.WhitelistFile)
			}
		}
	}

	file, err := os.Open(whitelistPath)
	if err != nil {
		return false, fmt.Sprintf("File whitelist tidak ditemukan di %s", whitelistPath)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		allowedPrefix := strings.TrimSpace(scanner.Text())
		if allowedPrefix == "" || strings.HasPrefix(allowedPrefix, "#") {
			continue
		}

		lowerCmd := strings.ToLower(cmdTrimmed)
		lowerPrefix := strings.ToLower(allowedPrefix)

		if strings.HasPrefix(lowerCmd, lowerPrefix) {
			// Pastikan prefix diikuti spasi atau end-of-string (word boundary)
			// agar "cat" tidak cocok dengan "cat /etc/passwd" kecuali "cat" memang di whitelist
			if len(lowerCmd) == len(lowerPrefix) || lowerCmd[len(lowerPrefix)] == ' ' {
				return true, ""
			}
		}
	}

	return false, fmt.Sprintf("Perintah '%s' diblokir karena tidak terdaftar di whitelist (%s)", cmdTrimmed, cfg.WhitelistFile)
}

// Middleware CORS & JSON Response
func jsonMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		next(w, r)
	}
}

// 1. Endpoint: POST /api/build -> Menjalankan build.sh di folder project
func handleBuild(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req BuildRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Payload JSON tidak valid"})
		return
	}

	if !validNameRegex.MatchString(req.Username) || !validNameRegex.MatchString(req.Framework) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Username atau Framework mengandung karakter ilegal"})
		return
	}

	// VALIDASI KEAMANAN: Pengecekan Whitelist untuk Action 5 (Custom Command)
	if req.Action == "5" {
		allowed, reason := isCommandAllowed(req.ExtraParam)
		if !allowed {
			w.WriteHeader(http.StatusForbidden)
			json.NewEncoder(w).Encode(ApiResponse{
				Status:  "error",
				Message: reason,
			})
			return
		}
	}

	projectFolder := fmt.Sprintf("website_%s_%s", req.Username, req.Framework)
	projectDir := filepath.Join(cfg.DocumentsBaseDir, projectFolder)
	buildScriptPath := filepath.Join(projectDir, "build.sh")

	if _, err := os.Stat(buildScriptPath); os.IsNotExist(err) {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("File build.sh tidak ditemukan di %s", buildScriptPath),
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.TimeoutMinutes)*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(ctx, "bash", buildScriptPath, req.Action, req.ExtraParam)
	cmd.Dir = projectDir

	outputBytes, err := cmd.CombinedOutput()
	outputStr := string(outputBytes)

	if ctx.Err() == context.DeadlineExceeded {
		w.WriteHeader(http.StatusRequestTimeout)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Proses build timeout (melebihi %d menit)", cfg.TimeoutMinutes),
			Output:  outputStr,
		})
		return
	}

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Gagal mengeksekusi build: %v", err),
			Output:  outputStr,
		})
		return
	}

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: fmt.Sprintf("Eksekusi build untuk %s berhasil", projectFolder),
		Output:  outputStr,
	})
}

// 2. Endpoint: POST /api/generate -> Men-generate project container baru
func handleGenerate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req GenerateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Payload JSON tidak valid"})
		return
	}

	if !validNameRegex.MatchString(req.Username) || !validNameRegex.MatchString(req.Framework) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Username atau Framework mengandung karakter ilegal"})
		return
	}

	var scriptName string
	switch strings.ToLower(req.Framework) {
	case "laravel":
		scriptName = "generate-laravel.sh"
	case "ci4", "codeigniter4":
		scriptName = "generate-ci4.sh"
	case "ci3", "codeigniter3":
		scriptName = "generate-ci3.sh"
	case "next", "nextjs", "react":
		scriptName = "generate-nextjs.sh"
	case "php", "native", "html", "nativephp":
		scriptName = "generate-php.sh"
	default:
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Framework '%s' belum didukung. Pilihan: laravel, ci4, ci3, nextjs, php", req.Framework),
		})
		return
	}

	scriptPath := filepath.Join(cfg.DeployBaseDir, scriptName)
	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Script generator %s tidak ditemukan", scriptPath),
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.TimeoutMinutes)*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(ctx, "bash", scriptPath, req.Username, req.GitRepo)
	cmd.Dir = cfg.DeployBaseDir

	outputBytes, err := cmd.CombinedOutput()
	outputStr := string(outputBytes)

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Gagal generate project: %v", err),
			Output:  outputStr,
		})
		return
	}

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: fmt.Sprintf("Project %s (%s) berhasil dibuat", req.Username, req.Framework),
		Output:  outputStr,
	})
}

// 3. Endpoint: POST /api/database/create -> Membuat database & user di database engine
func handleDatabaseCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req DatabaseCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Payload JSON tidak valid"})
		return
	}

	if req.Engine == "" {
		req.Engine = "mariadb"
	}

	if !validNameRegex.MatchString(req.Username) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Username mengandung karakter ilegal"})
		return
	}

	if req.DatabaseName != "" && !validNameRegex.MatchString(req.DatabaseName) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "DatabaseName mengandung karakter ilegal"})
		return
	}

	var dbScriptPath string
	switch strings.ToLower(req.Engine) {
	case "mariadb", "mysql":
		dbScriptPath = filepath.Join(cfg.DeployBaseDir, "db", "mariadb", "create-user-sql.sh")
	default:
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Database engine '%s' belum didukung. Pilihan: mariadb", req.Engine),
		})
		return
	}

	if _, err := os.Stat(dbScriptPath); os.IsNotExist(err) {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Script database %s tidak ditemukan", dbScriptPath),
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	var args []string
	args = append(args, "--user", req.Username)
	if req.DatabaseName != "" {
		args = append(args, "--db", req.DatabaseName)
	}

	cmd := exec.CommandContext(ctx, "bash", append([]string{dbScriptPath}, args...)...)
	cmd.Dir = filepath.Dir(dbScriptPath)

	outputBytes, err := cmd.CombinedOutput()
	outputStr := string(outputBytes)

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Gagal membuat database untuk user %s: %v", req.Username, err),
			Output:  outputStr,
		})
		return
	}

	finalDBName := fmt.Sprintf("user_%s", req.Username)
	if req.DatabaseName != "" {
		if strings.HasPrefix(req.DatabaseName, "user_") || strings.HasPrefix(req.DatabaseName, req.Username+"_") {
			finalDBName = req.DatabaseName
		} else {
			finalDBName = fmt.Sprintf("user_%s_%s", req.Username, req.DatabaseName)
		}
	}

	specificFile := fmt.Sprintf("/home/yopa/filebrowser/data/users/%s/DATABASE_%s.md", req.Username, finalDBName)
	masterFile := fmt.Sprintf("/home/yopa/filebrowser/data/users/%s/DATABASE.md", req.Username)

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: fmt.Sprintf("Database %s berhasil dibuat untuk engine %s", finalDBName, req.Engine),
		Output:  outputStr,
		Data: map[string]interface{}{
			"engine":                 req.Engine,
			"database":               finalDBName,
			"username":               req.Username,
			"host":                   "mariadb_container",
			"specific_credential_md": specificFile,
			"master_credential_md":   masterFile,
		},
	})
}

// 4. Endpoint: POST /api/container -> Kontrol Docker Compose (restart, stop, start, down, ps)
func handleContainer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req ContainerActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Payload JSON tidak valid"})
		return
	}

	allowedActions := map[string]bool{"restart": true, "stop": true, "start": true, "down": true, "ps": true}
	if !allowedActions[req.Action] {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Action harus salah satu dari: restart, stop, start, down, ps"})
		return
	}

	projectFolder := fmt.Sprintf("website_%s_%s", req.Username, req.Framework)
	projectDir := filepath.Join(cfg.DocumentsBaseDir, projectFolder)

	if _, err := os.Stat(filepath.Join(projectDir, "docker-compose.yml")); os.IsNotExist(err) {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("docker-compose.yml tidak ditemukan di %s", projectDir),
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker", "compose", req.Action)
	cmd.Dir = projectDir

	outputBytes, err := cmd.CombinedOutput()
	outputStr := string(outputBytes)

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Gagal menjalankan docker compose %s: %v", req.Action, err),
			Output:  outputStr,
		})
		return
	}

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: fmt.Sprintf("Docker compose %s berhasil untuk %s", req.Action, projectFolder),
		Output:  outputStr,
	})
}

// 5. Endpoint: POST /api/container/logs -> Mengambil log container dengan batasan jumlah baris (tail)
func handleContainerLogs(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req ContainerLogsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Payload JSON tidak valid"})
		return
	}

	if !validNameRegex.MatchString(req.Username) || !validNameRegex.MatchString(req.Framework) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Username atau Framework mengandung karakter ilegal"})
		return
	}

	tailLines := req.Tail
	if tailLines <= 0 {
		tailLines = 50
	} else if tailLines > 500 {
		tailLines = 500
	}

	projectFolder := fmt.Sprintf("website_%s_%s", req.Username, req.Framework)
	projectDir := filepath.Join(cfg.DocumentsBaseDir, projectFolder)

	if _, err := os.Stat(filepath.Join(projectDir, "docker-compose.yml")); os.IsNotExist(err) {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Project %s tidak ditemukan di %s", projectFolder, projectDir),
		})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	args := []string{"compose", "logs", "--tail", strconv.Itoa(tailLines), "--no-log-prefix"}
	if req.Service != "" {
		serviceTrimmed := strings.TrimSpace(strings.ToLower(req.Service))
		if serviceTrimmed == "app" || serviceTrimmed == "nginx" {
			args = append(args, serviceTrimmed)
		}
	}

	cmd := exec.CommandContext(ctx, "docker", args...)
	cmd.Dir = projectDir

	outputBytes, err := cmd.CombinedOutput()
	outputStr := string(outputBytes)

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "error",
			Message: fmt.Sprintf("Gagal mengambil log container: %v", err),
			Output:  outputStr,
		})
		return
	}

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: fmt.Sprintf("Berhasil mengambil %d baris log untuk %s", tailLines, projectFolder),
		Output:  outputStr,
		Data: map[string]interface{}{
			"username":   req.Username,
			"framework":  req.Framework,
			"tail_lines": tailLines,
			"service":    req.Service,
		},
	})
}

// 6. Endpoint: GET /api/list -> Membaca data port.csv
func handleList(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	csvPath := filepath.Join(cfg.DeployBaseDir, "port.csv")
	file, err := os.Open(csvPath)
	if err != nil {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(ApiResponse{
			Status:  "success",
			Message: "File port.csv belum ada (belum ada project dibuat)",
			Data:    []interface{}{},
		})
		return
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Gagal parse file port.csv"})
		return
	}

	type WebItem struct {
		Username  string `json:"username"`
		Framework string `json:"framework"`
		PortApp   string `json:"port_app"`
		PortWWW   string `json:"port_www"`
		CreatedAt string `json:"created_at"`
	}

	var list []WebItem
	for i, row := range records {
		if i == 0 || len(row) < 5 {
			continue
		}
		list = append(list, WebItem{
			Username:  row[0],
			Framework: row[1],
			PortApp:   row[2],
			PortWWW:   row[3],
			CreatedAt: row[4],
		})
	}

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: "Daftar website berhasil dimuat",
		Data:    list,
	})
}

// 7. Endpoint: GET /api/whitelist -> Melihat daftar perintah yang ada di whitelist
func handleWhitelist(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, `{"status":"error","message":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	whitelistPath := cfg.WhitelistFile
	if !filepath.IsAbs(whitelistPath) {
		if _, err := os.Stat(whitelistPath); os.IsNotExist(err) {
			whitelistPath = filepath.Join("api", cfg.WhitelistFile)
			if _, err := os.Stat(whitelistPath); os.IsNotExist(err) {
				whitelistPath = filepath.Join(cfg.DeployBaseDir, "api", cfg.WhitelistFile)
			}
		}
	}

	file, err := os.Open(whitelistPath)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ApiResponse{Status: "error", Message: "Gagal membuka file whitelist"})
		return
	}
	defer file.Close()

	var allowedList []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		allowedList = append(allowedList, line)
	}

	json.NewEncoder(w).Encode(ApiResponse{
		Status:  "success",
		Message: "Daftar whitelist perintah",
		Data:    allowedList,
	})
}

// 8. Endpoint: GET /api/health -> Health Check
func handleHealth(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "healthy",
		"timestamp": time.Now().Format(time.RFC3339),
		"config": map[string]interface{}{
			"documents_dir": cfg.DocumentsBaseDir,
			"deploy_dir":    cfg.DeployBaseDir,
			"timeout_mins":  cfg.TimeoutMinutes,
			"whitelist":     cfg.WhitelistFile,
		},
	})
}

func main() {
	initConfig()

	mux := http.NewServeMux()
	mux.HandleFunc("/api/build", jsonMiddleware(handleBuild))
	mux.HandleFunc("/api/generate", jsonMiddleware(handleGenerate))
	mux.HandleFunc("/api/database/create", jsonMiddleware(handleDatabaseCreate))
	mux.HandleFunc("/api/container", jsonMiddleware(handleContainer))
	mux.HandleFunc("/api/container/logs", jsonMiddleware(handleContainerLogs))
	mux.HandleFunc("/api/list", jsonMiddleware(handleList))
	mux.HandleFunc("/api/whitelist", jsonMiddleware(handleWhitelist))
	mux.HandleFunc("/api/health", jsonMiddleware(handleHealth))

	fmt.Println("==================================================")
	fmt.Printf("🚀 Deploy Manager API Server berjalan di %s\n", cfg.Port)
	fmt.Printf("📁 Documents Base Dir : %s\n", cfg.DocumentsBaseDir)
	fmt.Printf("📁 Deploy Base Dir    : %s\n", cfg.DeployBaseDir)
	fmt.Printf("🛡️  Whitelist File     : %s\n", cfg.WhitelistFile)
	fmt.Println("==================================================")

	server := &http.Server{
		Addr:         cfg.Port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: time.Duration(cfg.TimeoutMinutes+1) * time.Minute,
	}

	log.Fatal(server.ListenAndServe())
}
