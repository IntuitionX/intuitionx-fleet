#!/bin/bash

# Rollback script for Fleet VPS deployment
# Usage: ./scripts/rollback.sh [backup_timestamp]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment variables
if [ -f "$PROJECT_DIR/.env.production" ]; then
  source "$PROJECT_DIR/.env.production"
elif [ -f "$PROJECT_DIR/.env" ]; then
  source "$PROJECT_DIR/.env"
fi

VPS_HOST=${VPS_HOST:-}
VPS_USER=${VPS_USER:-}
VPS_APP_PATH=${VPS_APP_PATH:-/var/www/intuitionx-fleet}
SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}

if [ -z "$VPS_HOST" ] || [ -z "$VPS_USER" ]; then
  echo "Error: VPS_HOST and VPS_USER must be set"
  exit 1
fi

BACKUP_TIMESTAMP=$1

if [ -z "$BACKUP_TIMESTAMP" ]; then
  echo "Available backups:"
  ssh -i "$SSH_KEY_PATH" "$VPS_USER@$VPS_HOST" "ls -la $VPS_APP_PATH/backups/ | grep '^d' | tail -5"
  echo ""
  echo "Usage: ./scripts/rollback.sh YYYYMMDD_HHMMSS"
  exit 1
fi

echo "Rolling back to backup: $BACKUP_TIMESTAMP"

ssh -i "$SSH_KEY_PATH" "$VPS_USER@$VPS_HOST" << ENDSSH
  set -e

  cd $VPS_APP_PATH

  BACKUP_DIR="backups/$BACKUP_TIMESTAMP"

  if [ ! -d "\$BACKUP_DIR" ]; then
    echo "Backup not found: \$BACKUP_DIR"
    exit 1
  fi

  echo "Restoring from backup..."

  # Stop containers
  docker compose -f docker-compose.production.yml down || true

  # Restore docker-compose.yml if available
  if [ -f "\$BACKUP_DIR/docker-compose.yml" ]; then
    cp "\$BACKUP_DIR/docker-compose.yml" docker-compose.production.yml
  fi

  # Show recent commits for manual rollback
  echo "Recent commits:"
  git log --oneline -10

  # Restart containers
  docker compose -f docker-compose.production.yml up -d --build

  echo "Rollback completed!"
ENDSSH

echo "Rollback completed!"
