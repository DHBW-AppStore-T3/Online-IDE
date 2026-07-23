#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Online-IDE Provisioning Script
# Ziel: code-server (VS Code im Browser) installieren und systemd-ready machen
#
# Wichtig:
# - KEINE User anlegen (kommt später via cloud-init)
# - KEINE Passwörter setzen
# - KEINE kurs-/teamspezifischen Daten
# - Generisches, wiederverwendbares Image
# -----------------------------------------------------------------------------

echo "[1/5] Waiting for cloud-init to complete..."
cloud-init status --wait || true

echo "[2/5] Updating package lists and installing dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl \
  wget \
  git \
  build-essential \
  python3 \
  python3-pip \
  nodejs \
  npm \
  unzip

# -----------------------------------------------------------------------------
# code-server Installation
# -----------------------------------------------------------------------------
echo "[3/5] Installing code-server..."

# Offizielle Installation via Install-Script
curl -fsSL https://code-server.dev/install.sh | sh

# code-server systemd-Service wird automatisch erstellt, aber nicht gestartet
# (wird pro User via cloud-init gestartet)

echo "[4/5] Configuring code-server defaults..."

# Globale config für code-server (wird von userspezifischen configs überschrieben)
sudo mkdir -p /etc/code-server

# Default-Config: lauscht auf allen Interfaces, Port 8080
sudo tee /etc/code-server/config.yaml >/dev/null << 'EOF'
bind-addr: 0.0.0.0:8080
auth: password
cert: false
EOF

echo "[5/5] Cleanup and finalization..."

# Apt-Cache leeren für kleineres Image
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# machine-id zurücksetzen (wichtig für cloud-init)
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

echo "✓ Provisioning finished. Image is ready for deployment."
