#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Online-IDE Provisioning Script
# Goal: Install code-server (VS Code in the browser) and make it systemd-ready
#
# Important:
# - Do NOT create users (handled later via cloud-init)
# - Do NOT set passwords
# - Do NOT include course- or team-specific data
# - Generic, reusable image
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

curl -fsSL https://code-server.dev/install.sh | sh

# The systemd service is created automatically but not started here;
# it is started per user via cloud-init.

echo "[4/5] Configuring code-server defaults..."

# Global config for code-server (overridden by per-user configs)
sudo mkdir -p /etc/code-server

# Default config: listen on all interfaces, port 8080
sudo tee /etc/code-server/config.yaml >/dev/null << 'EOF'
bind-addr: 0.0.0.0:8080
auth: password
cert: false
EOF

echo "[5/5] Cleanup and finalization..."

# Clear apt cache to reduce image size
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Reset machine-id so cloud-init generates a fresh one on first boot
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

echo "✓ Provisioning finished. Image is ready for deployment."
