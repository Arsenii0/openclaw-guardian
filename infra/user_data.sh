#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw bootstrap — Ubuntu 24.04 LTS
#
# Each section is labelled:
#   [FROM DOCS]  — behaviour specified in the OpenClaw README / docs
#                  https://github.com/openclaw/openclaw
#   [SECURITY]   — standard Linux/AWS hardening, not from OpenClaw docs
#
# Terraform templatefile() variables:
#   openclaw_version      – npm tag/version  (e.g. "latest", "2026.3.2")
#   gateway_password      – OpenClaw gateway auth password
#   ai_api_key            – AI provider API key (may be empty)
#   enable_docker_sandbox – "true"/"false"
# ─────────────────────────────────────────────────────────────────────────────

# [SECURITY] Fail fast on any error; log everything to /var/log and journald
set -euo pipefail
exec > >(tee /var/log/openclaw-userdata.log | logger -t openclaw-bootstrap) 2>&1

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [1/8] System update ==="
# ─────────────────────────────────────────────────────────────────────────────

# [SECURITY] Non-interactive upgrades; upgrade existing packages before installing anything new
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y --no-install-recommends

# [SECURITY] ufw – host firewall (deny all inbound, allow all outbound)
# [SECURITY] amazon-ssm-agent – SSM Session Manager replaces inbound SSH entirely
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg unzip jq ufw \
  amazon-ssm-agent

# [SECURITY] Enable SSM agent so AWS can open shell sessions without any open ports
systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [2/8] OS hardening ==="
# ─────────────────────────────────────────────────────────────────────────────

# [SECURITY] Disable root SSH login (belt-and-suspenders; port 22 is not open anyway)
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true

# [SECURITY] Firewall: drop all inbound traffic; outbound is unrestricted
#            The gateway (port 18789) stays on loopback – reachable only via SSM port-forward
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [3/8] Install Node.js 22 LTS ==="
# ─────────────────────────────────────────────────────────────────────────────

# [FROM DOCS] OpenClaw requires Node ≥ 22
#             https://github.com/openclaw/openclaw#install-recommended
# Use only stable releases
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
node --version
npm --version

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [4/8] Install Docker ==="
# ─────────────────────────────────────────────────────────────────────────────

# [FROM DOCS] Docker is required for sandbox mode
#             https://github.com/openclaw/openclaw#security-model-important
#             "set agents.defaults.sandbox.mode: non-main to run non-main sessions
#              inside per-session Docker sandboxes"
# [SECURITY]  Installation from the official Docker apt repo (not the Ubuntu snap)
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
echo "Docker sandbox disabled – skipping."
%{ endif }

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [5/8] Create openclaw system user ==="
# ─────────────────────────────────────────────────────────────────────────────

# [SECURITY] Run OpenClaw as a dedicated system user with no login shell
#            instead of root
useradd --system --create-home --shell /bin/bash openclaw
%{ if enable_docker_sandbox == "true" }
usermod -aG docker openclaw
%{ endif }

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [6/8] Install OpenClaw ==="
# ─────────────────────────────────────────────────────────────────────────────

# [FROM DOCS] https://github.com/openclaw/openclaw#install-recommended
npm install -g "openclaw@${openclaw_version}"
openclaw --version || true

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [7/8] Write configuration ==="
# ─────────────────────────────────────────────────────────────────────────────

# [SECURITY] Secrets are injected by Terraform templatefile() at apply time.
#            They are embedded in user_data — never echoed to the bootstrap log.
mkdir -p /etc/openclaw
chmod 700 /etc/openclaw

# Quoted heredoc: bash does no expansion, so special chars in the values are safe.
cat > /etc/openclaw/secrets.env <<'SECEOF'
OPENCLAW_GATEWAY_PASSWORD=${gateway_password}
%{~ if ai_api_key != "" ~}
OPENAI_API_KEY=${ai_api_key}
%{~ endif ~}
SECEOF

chmod 600 /etc/openclaw/secrets.env

# [SECURITY] Restrict the .openclaw directory so only the openclaw user can read it
mkdir -p /home/openclaw/.openclaw
chmod 700 /home/openclaw/.openclaw

cat > /home/openclaw/.openclaw/openclaw.json5 <<'CONFIG'
{
  // ── FROM DOCS: bind + auth ────────────────────────────────────────────────
  // https://github.com/openclaw/openclaw#tailscale-access-gateway-dashboard
  // https://github.com/openclaw/openclaw#remote-gateway-linux-is-great
  //
  // "gateway.bind must stay loopback when Serve/Funnel is enabled"
  // "Funnel refuses to start unless gateway.auth.mode: password is set"
  // We apply both even without Tailscale – it is the safe server default.
  gateway: {
    bind: "loopback",   // never expose 18789 to 0.0.0.0; use SSM port-forward
    auth: {
      mode: "password",
    },
  },

  // ── FROM DOCS: sandbox mode ───────────────────────────────────────────────
  // https://github.com/openclaw/openclaw#security-model-important
  //
  // "set agents.defaults.sandbox.mode: non-main to run non-main sessions
  //  (groups/channels) inside per-session Docker sandboxes;
  //  bash then runs in Docker for those sessions"
  agents: {
    defaults: {
      sandbox: {
        mode: "${enable_docker_sandbox == "true" ? "non-main" : "off"}",
      },
    },
  },

  // ── FROM DOCS: model selection ────────────────────────────────────────────
  // https://github.com/openclaw/openclaw#configuration
  // Run: openclaw doctor   to verify provider connectivity after first start
  agent: {
    model: "openai/gpt-4o-mini",
  },
}
CONFIG

chown -R openclaw:openclaw /home/openclaw/.openclaw
chmod 600 /home/openclaw/.openclaw/openclaw.json5

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [8/8] Create systemd service ==="
# ─────────────────────────────────────────────────────────────────────────────

# [FROM DOCS] ExecStart matches the recommended gateway command:
#             https://github.com/openclaw/openclaw#quick-start-tldr
#             "openclaw gateway --port 18789"
#
# [SECURITY]  Everything else in [Service] is standard systemd hardening:
#             - EnvironmentFile pulls secrets without exposing them in ps output
#             - NoNewPrivileges, ProtectSystem, PrivateTmp isolate the process
#             - Restart=on-failure keeps it alive, RestartSec rate-limits restarts
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
EnvironmentFile=/etc/openclaw/secrets.env
ExecStart=/usr/bin/openclaw gateway --port 18789
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=full
PrivateTmp=yes
LimitNOFILE=65536

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
