#!/bin/bash

# =======================================================
# Setup Environment for Docker Deploy System
# =======================================================

echo "========================================"
echo " 🚀 Setting up system dependencies & permissions"
echo "========================================"

# 1. Menambahkan user ke grup docker agar tidak membutuhkan 'sudo' saat eksekusi docker command
CURRENT_USER=$(whoami)
echo "[INFO] Menambahkan user '${CURRENT_USER}' ke grup 'docker'..."
sudo usermod -aG docker "$CURRENT_USER"

# 2. Memastikan service docker dan permissions socket aman
echo "[INFO] Memastikan permissions docker socket..."
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

echo "========================================"
echo " [SUCCESS] Setup selesai!"
echo " Silakan jalankan 'newgrp docker' atau relogin untuk mengaktifkan grup baru."
echo "========================================"
