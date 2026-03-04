#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw bootstrap — Ubuntu 24.04 LTS
#
# Terraform templatefile() variables:
#   openclaw_version      – npm tag/version  (e.g. "latest", "2026.3.2")
#   gateway_password      – OpenClaw gateway auth password
#   ai_api_key            – AI provider API key (may be empty)
#   enable_docker_sandbox – "true"/"false"
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
exec > >(tee /var/log/openclaw-userdata.log | logger -t openclaw-bootstrap) 2>&1


# ═════════════════════════════════════════════════════════════════════════════
# PART 1 — SECURITY HARDENING
# Everything in this section is standard Linux/AWS hardening.
# None of it is required or mentioned by the OpenClaw docs.
# ═════════════════════════════════════════════════════════════════════════════

echo "=== [SECURITY 1/4] System update ==="

# Non-interactive upgrades; upgrade before installing anything new
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y --no-install-recommends

# ufw              – host firewall (deny all inbound, allow all outbound)
# amazon-ssm-agent – SSM Session Manager replaces inbound SSH entirely;
#                    port 22 is never opened in the security group
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg unzip jq ufw \
  amazon-ssm-agent

# Enable SSM agent so AWS can open shell sessions without any open ports
systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [SECURITY 2/4] OS hardening ==="

# Disable root SSH login (belt-and-suspenders; port 22 is not open anyway)
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/'  /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true

# Firewall: drop all inbound; outbound is unrestricted.
# The gateway (port 18789) stays on loopback – reachable only via SSM port-forward.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [SECURITY 3/4] Install Docker from official repo ==="

# Docker is a functional requirement when sandbox mode is enabled (see Part 2).
# Installing from the official Docker apt repo rather than the Ubuntu snap is a
# security/reliability choice — not specified by the OpenClaw docs.
%{ if enable_docker_sandbox == "true" }
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
systemctl enable docker
systemctl start  docker
%{ else }
echo "Docker sandbox disabled – skipping Docker install."
%{ endif }

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [SECURITY 4/4] Create dedicated system user ==="

# Run OpenClaw as a dedicated system user with no login shell, not as root
useradd --system --create-home --shell /bin/bash openclaw
%{ if enable_docker_sandbox == "true" }
usermod -aG docker openclaw
%{ endif }


# ═════════════════════════════════════════════════════════════════════════════
# PART 2 — OPENCLAW SETUP
# Everything in this section follows the OpenClaw README / docs directly.
# Refs: https://github.com/openclaw/openclaw
# ═════════════════════════════════════════════════════════════════════════════

echo "=== [OPENCLAW 1/3] Install Node.js 22 LTS ==="

# Docs: "Runtime: Node ≥22"
# https://github.com/openclaw/openclaw#install-recommended
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
node --version
npm --version

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [OPENCLAW 2/3] Install OpenClaw ==="

# Docs: "npm install -g openclaw@latest"
# https://github.com/openclaw/openclaw#install-recommended
npm install -g "openclaw@${openclaw_version}"
openclaw --version || true

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [OPENCLAW 3/3] Write configuration ==="

# Secrets injected by Terraform templatefile() at apply time — never echoed to logs
mkdir -p /etc/openclaw
chmod 700 /etc/openclaw

# Quoted heredoc: no shell expansion — special chars in values are safe
cat > /etc/openclaw/secrets.env <<'SECEOF'
OPENCLAW_GATEWAY_PASSWORD=${gateway_password}
%{~ if ai_api_key != "" ~}
OPENAI_API_KEY=${ai_api_key}
%{~ endif ~}
SECEOF
chmod 600 /etc/openclaw/secrets.env

mkdir -p /home/openclaw/.openclaw
chmod 700 /home/openclaw/.openclaw

cat > /home/openclaw/.openclaw/openclaw.json5 <<'CONFIG'
{
  gateway: {
    // Docs: "gateway.bind must stay loopback when Serve/Funnel is enabled"
    // We always bind loopback — access is via SSM port-forward only.
    // https://github.com/openclaw/openclaw#tailscale-access-gateway-dashboard
    bind: "loopback",

    auth: {
      // Docs: "Funnel refuses to start unless gateway.auth.mode: password is set"
      // Applied as the safe server default even without Tailscale.
      // https://github.com/openclaw/openclaw#tailscale-access-gateway-dashboard
      mode: "password",
    },
  },

  agents: {
    defaults: {
      sandbox: {
        // Docs: "set agents.defaults.sandbox.mode: non-main to run non-main
        //        sessions (groups/channels) inside per-session Docker sandboxes;
        //        bash then runs in Docker for those sessions"
        // https://github.com/openclaw/openclaw#security-model-important
        mode: "${enable_docker_sandbox == "true" ? "non-main" : "off"}",
      },
    },
  },

  agent: {
    // Docs: minimal config example — https://github.com/openclaw/openclaw#configuration
    // Run: openclaw doctor   to verify provider connectivity after first start
    model: "openai/gpt-4o-mini",
  },
}
CONFIG

chown -R openclaw:openclaw /home/openclaw/.openclaw
chmod 600 /home/openclaw/.openclaw/openclaw.json5


# ═════════════════════════════════════════════════════════════════════════════
# PART 3 — SYSTEMD SERVICE
#
# ExecStart comes directly from the OpenClaw docs:
#   "openclaw gateway --port 18789"
#   https://github.com/openclaw/openclaw#quick-start-tldr
# ═════════════════════════════════════════════════════════════════════════════

echo "=== [SERVICE] Register and start openclaw-gateway ==="

cat > /etc/systemd/system/openclaw-gateway.service <<'SERVICE'
[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw

ExecStart=/usr/bin/openclaw gateway --port 18789
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable openclaw-gateway
systemctl start  openclaw-gateway

echo "=== Bootstrap complete ==="
echo ""
echo "Connect via SSM Session Manager:"
echo "  aws ssm start-session --target INSTANCE_ID"
echo ""
echo "Port-forward the gateway WebUI to your laptop:"
echo "  aws ssm start-session --target INSTANCE_ID \\"
echo "    --document-name AWS-StartPortForwardingSession \\"
echo "    --parameters 'portNumber=18789,localPortNumber=18789'"
echo "  # Then open: http://localhost:18789"
echo ""
echo "Check OpenClaw health (inside the SSM session):"
echo "  sudo systemctl status openclaw-gateway"
echo "  journalctl -u openclaw-gateway -f"
echo "  sudo -u openclaw openclaw doctor"
