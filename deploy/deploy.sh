#!/bin/bash
# Redeploys the checked-out commit: refreshes .env from SSM, then rebuilds and restarts the production stack.
# Run on the server as root, by the SSM deploy document (see terraform/main.tf) or by hand.
set -euo pipefail

# SSM commands and cloud-init may run without HOME, which git and the Docker CLI expect
export HOME="${HOME:-/root}"

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

echo "Deploying $(git rev-parse --short HEAD): $(git log -1 --format=%s)"

./deploy/render-env.sh

# --wait returns once services are healthy (and migrate has completed), and fails if any of them don't
docker compose -f compose.yaml -f docker-compose.prod.yaml up -d --build --wait --remove-orphans

docker image prune -f
echo "Deploy finished"
