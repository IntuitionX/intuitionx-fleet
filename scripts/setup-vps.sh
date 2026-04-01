#!/bin/bash

# Setup script for Hostinger VPS
# Run this script on your VPS to prepare it for Fleet deployment
# Usage: sudo bash scripts/setup-vps.sh

set -e

echo "Setting up Hostinger VPS for IntuitionX Fleet deployment..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo"
  exit 1
fi

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y \
  curl \
  git \
  wget \
  unzip \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release

# Install Docker
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
else
  echo "Docker is already installed"
fi

# Install Docker Compose plugin (v2)
if ! docker compose version &> /dev/null; then
  echo "Installing Docker Compose plugin..."
  apt install -y docker-compose-plugin
else
  echo "Docker Compose is already installed"
fi

# Create application directory
APP_DIR="/var/www/intuitionx-fleet"
echo "Creating application directory: $APP_DIR"
mkdir -p "$APP_DIR"
if [ -n "$SUDO_USER" ]; then
  chown "$SUDO_USER:$SUDO_USER" "$APP_DIR"
fi

# Create backup directory
BACKUP_DIR="$APP_DIR/backups"
mkdir -p "$BACKUP_DIR"
if [ -n "$SUDO_USER" ]; then
  chown "$SUDO_USER:$SUDO_USER" "$BACKUP_DIR"
fi

# Install Nginx (optional, for reverse proxy)
read -p "Do you want to install Nginx for reverse proxy? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Installing Nginx..."
  apt install -y nginx
  systemctl enable nginx
  systemctl start nginx
  echo "Nginx installed and started"
fi

# Configure firewall
read -p "Do you want to configure UFW firewall? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Configuring firewall..."
  apt install -y ufw

  ufw allow 22/tcp   # SSH
  ufw allow 80/tcp   # HTTP
  ufw allow 443/tcp  # HTTPS
  ufw allow 8080/tcp # Fleet server

  ufw --force enable
  echo "Firewall configured"
fi

# Install Certbot for SSL (optional)
read -p "Do you want to install Certbot for SSL certificates? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Installing Certbot..."
  apt install -y certbot python3-certbot-nginx
  echo "Certbot installed"
  echo "Run 'sudo certbot --nginx -d yourdomain.com' to get SSL certificate"
fi

# Verify installations
echo ""
echo "Verification:"
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"
echo "Git version: $(git --version)"

echo ""
echo "VPS setup completed!"
echo ""
echo "Next steps:"
echo "1. Set up SSH key authentication from your local machine"
echo "2. Clone your repository: cd $APP_DIR && git clone <your-repo-url> ."
echo "3. Create .env.production file with your configuration (see .env.production.example)"
echo "4. Configure GitHub Secrets for CI/CD:"
echo "   - VPS_SSH_PRIVATE_KEY: Your SSH private key"
echo "   - VPS_HOST: Your VPS IP or domain"
echo "   - VPS_USER: SSH username (e.g., root)"
echo "   - VPS_APP_PATH: $APP_DIR"
echo "5. Push to main branch to trigger deployment"
