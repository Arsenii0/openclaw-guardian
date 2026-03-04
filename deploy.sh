#!/bin/bash
# OpenClaw Infrastructure Deployment
# Provisions a secure EC2 instance running the OpenClaw gateway.

set -e

echo "=== OpenClaw Infrastructure Deployment ==="

AWS_PROFILE="${AWS_PROFILE:-personal}"

# ── Auth check ────────────────────────────────────────────────────────────────

if [ ! -f "$HOME/.aws/config" ]; then
  echo "❌ AWS config not found at $HOME/.aws/config"
  echo "   Run: aws configure sso --profile $AWS_PROFILE"
  exit 1
fi

if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  echo "❌ AWS SSO session not active for profile '$AWS_PROFILE'"
  echo "   Run: aws sso login --profile $AWS_PROFILE"
  exit 1
fi

echo "✅ AWS SSO session active (profile: $AWS_PROFILE)"

# ── Build and run deployment container ───────────────────────────────────────

echo "Building deployment container..."
docker build -f Dockerfile.deploy -t openclaw-deploy .

echo "Starting deployment container..."
docker run -it --rm \
    --network host \
    --dns 8.8.8.8 \
    --dns 1.1.1.1 \
    -e AWS_PROFILE="$AWS_PROFILE" \
    -v "$(pwd)/infra:/workspace/infra" \
    -v "$HOME/.aws:/root/.aws:ro" \
    -w /workspace/infra \
    openclaw-deploy bash
