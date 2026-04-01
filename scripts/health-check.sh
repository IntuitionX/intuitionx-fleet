#!/bin/bash

# Health check script for Fleet VPS deployment
# Usage: ./scripts/health-check.sh

set -e

FLEET_URL=${FLEET_URL:-http://localhost:8080}
MAX_ATTEMPTS=30
ATTEMPT=0

echo "Running health checks..."

# Check if containers are running
echo "Checking container status..."
docker compose -f docker-compose.production.yml ps

# Check Fleet server
echo "Checking Fleet server health..."
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -f "$FLEET_URL/healthz" > /dev/null 2>&1; then
    echo "Fleet server is healthy!"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS..."
  sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "Fleet server health check failed"
  echo "Recent logs:"
  docker compose -f docker-compose.production.yml logs --tail=50 fleet
  exit 1
fi

# Check MySQL
echo "Checking MySQL health..."
if docker compose -f docker-compose.production.yml exec -T mysql mysqladmin ping -h localhost -u root -ptoor > /dev/null 2>&1; then
  echo "MySQL is healthy!"
else
  echo "MySQL health check failed"
  exit 1
fi

# Check Redis
echo "Checking Redis health..."
if docker compose -f docker-compose.production.yml exec -T redis redis-cli ping > /dev/null 2>&1; then
  echo "Redis is healthy!"
else
  echo "Redis health check failed"
  exit 1
fi

echo "All health checks passed!"
