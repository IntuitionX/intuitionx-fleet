#!/bin/bash

# Deployment script for Hostinger VPS
# Usage: ./scripts/deploy.sh [environment]

set -e

ENVIRONMENT=${1:-production}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f "$PROJECT_DIR/.env.$ENVIRONMENT" ]; then
  source "$PROJECT_DIR/.env.$ENVIRONMENT"
elif [ -f "$PROJECT_DIR/.env" ]; then
  source "$PROJECT_DIR/.env"
fi

# Required variables
VPS_HOST=${VPS_HOST:-}
VPS_USER=${VPS_USER:-}
VPS_APP_PATH=${VPS_APP_PATH:-/var/www/intuitionx-fleet}
SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}

echo -e "${GREEN}Starting deployment to $ENVIRONMENT...${NC}"

# Validate required variables
if [ -z "$VPS_HOST" ] || [ -z "$VPS_USER" ]; then
  echo -e "${RED}Error: VPS_HOST and VPS_USER must be set${NC}"
  echo "Set them in .env.$ENVIRONMENT or .env file"
  exit 1
fi

# Check SSH key
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo -e "${YELLOW}SSH key not found at $SSH_KEY_PATH${NC}"
  echo "Please ensure your SSH key is set up for passwordless access"
fi

# Test SSH connection
echo -e "${GREEN}Testing SSH connection...${NC}"
if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 "$VPS_USER@$VPS_HOST" "echo 'SSH connection successful'" > /dev/null 2>&1; then
  echo -e "${RED}Failed to connect to VPS${NC}"
  exit 1
fi

# Deploy function
deploy() {
  ssh -i "$SSH_KEY_PATH" "$VPS_USER@$VPS_HOST" << ENDSSH
    set -e

    echo "Navigating to application directory..."
    cd $VPS_APP_PATH || {
      echo "Application directory not found: $VPS_APP_PATH"
      echo "Creating directory..."
      sudo mkdir -p $VPS_APP_PATH
      sudo chown \$USER:\$USER $VPS_APP_PATH
    }

    cd $VPS_APP_PATH

    # Check if git repository exists
    if [ ! -d .git ]; then
      echo "Cloning repository..."
      git clone $GIT_REPO_URL . || {
        echo "Failed to clone repository"
        exit 1
      }
    fi

    # Pull latest code
    echo "Pulling latest code..."
    git fetch origin
    CURRENT_BRANCH=\$(git rev-parse --abbrev-ref HEAD)
    git reset --hard origin/\$CURRENT_BRANCH

    # Create backup
    echo "Creating backup..."
    BACKUP_DIR="backups/\$(date +%Y%m%d_%H%M%S)"
    mkdir -p "\$BACKUP_DIR"

    if [ -f docker-compose.production.yml ]; then
      docker compose -f docker-compose.production.yml ps > "\$BACKUP_DIR/containers.txt" 2>/dev/null || true
      docker compose -f docker-compose.production.yml config > "\$BACKUP_DIR/docker-compose.yml" 2>/dev/null || true
    fi

    # Copy environment file if it exists
    if [ -f .env.production ]; then
      echo "Updating environment file..."
      cp .env.production .env
    elif [ -f .env ]; then
      echo "Using existing .env file..."
    else
      echo "No .env file found. Please create .env.production or .env"
    fi

    # Stop existing containers
    echo "Stopping existing containers..."
    docker compose -f docker-compose.production.yml down || true

    # Build and start containers
    echo "Building and starting containers..."
    docker compose -f docker-compose.production.yml build --no-cache
    docker compose -f docker-compose.production.yml up -d

    # Wait for services
    echo "Waiting for services to start..."
    sleep 20

    # Health check
    echo "Running health checks..."
    max_attempts=30
    attempt=0

    while [ \$attempt -lt \$max_attempts ]; do
      if curl -f http://localhost:8080/healthz > /dev/null 2>&1; then
        echo "Fleet server is healthy!"
        break
      fi
      attempt=\$((attempt + 1))
      echo "Attempt \$attempt/\$max_attempts..."
      sleep 5
    done

    if [ \$attempt -eq \$max_attempts ]; then
      echo "Health check timeout. Check logs:"
      docker compose -f docker-compose.production.yml logs --tail=50
      exit 1
    fi

    # Cleanup
    echo "Cleaning up old Docker images..."
    docker image prune -f || true

    # Show status
    echo "Deployment status:"
    docker compose -f docker-compose.production.yml ps

    echo "Deployment completed successfully!"
ENDSSH
}

# Run deployment
deploy

echo -e "${GREEN}Deployment completed!${NC}"
echo -e "${GREEN}Fleet should be available at: http://$VPS_HOST:8080${NC}"
