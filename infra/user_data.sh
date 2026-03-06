#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw bootstrap — Ubuntu 24.04 LTS



# ═════════════════════════════════════════════════════════════════════════════
# PART 1 — SECURITY HARDENING
# ═════════════════════════════════════════════════════════════════════════════

# Non-interactive upgrades; upgrade before installing anything new
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y --no-install-recommends

apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg unzip jq ufw \
  amazon-ssm-agent

# Enable SSM agent so AWS can open shell sessions without any open ports
systemctl enable amazon-ssm-agent
systemctl start  amazon-ssm-agent

# ─────────────────────────────────────────────────────────────────────────────
echo "=== OS hardening ==="

# Disable root SSH login (belt-and-suspenders; port 22 is not open anyway)
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/'  /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true

# Firewall: drop all inbound; outbound is unrestricted.
# The gateway (port 18789) stays on loopback – reachable only via SSM port-forward.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from ${vnc_allowed_cidr} to any port 5901 proto tcp comment "VNC"
ufw --force enable

# ═════════════════════════════════════════════════════════════════════════════
# PART 2 — OPENCLAW SETUP
# ═════════════════════════════════════════════════════════════════════════════

echo "=== [OPENCLAW 1/2] Install Node.js 22 LTS ==="

# Docs: "Runtime: Node ≥22"
# https://github.com/openclaw/openclaw#install-recommended
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
node --version
npm --version

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [OPENCLAW 2/2] Install OpenClaw ==="

npm install -g "openclaw@${openclaw_version}"
openclaw --version || true


# ═════════════════════════════════════════════════════════════════════════════
# PART 3 — DESKTOP + VNC
# XFCE is used instead of full GNOME — much lighter, fine on t3.medium.
# TigerVNC is the server; connects on port 5901 (display :1).
# ═════════════════════════════════════════════════════════════════════════════

echo "=== [DESKTOP 1/2] Install XFCE desktop + TigerVNC + Firefox ==="

# Snap-based Firefox does not work inside a VNC session (no systemd user session).
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  > /etc/apt/sources.list.d/mozilla.list
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
  > /etc/apt/preferences.d/mozilla
apt-get update -y

apt-get install -y \
  xubuntu-desktop \
  tigervnc-standalone-server \
  tigervnc-common \
  dbus-x11 \
  xterm \
  firefox

# ─────────────────────────────────────────────────────────────────────────────
echo "=== [DESKTOP 2/2] Configure TigerVNC for ubuntu user ==="

VNC_USER=ubuntu
VNC_HOME=/home/$VNC_USER

mkdir -p "$VNC_HOME/.vnc"

# Set VNC password non-interactively (-f writes the binary passwd file to stdout)
printf '%s' "${vnc_password}" | vncpasswd -f > "$VNC_HOME/.vnc/passwd"
chmod 600 "$VNC_HOME/.vnc/passwd"

# xstartup: launch XFCE session
cat > "$VNC_HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XSTARTUP
chmod +x "$VNC_HOME/.vnc/xstartup"

chown -R "$VNC_USER:$VNC_USER" "$VNC_HOME/.vnc"

# Systemd service — runs VNC on display :1 (port 5901) as the ubuntu user
cat > /etc/systemd/system/vncserver@.service <<'VNCSERVICE'
[Unit]
Description=TigerVNC server on display %i
After=network.target syslog.target

[Service]
Type=forking
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu

ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :%i -geometry 1920x1080 -depth 24 -localhost no
ExecStop=/usr/bin/vncserver -kill :%i

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
VNCSERVICE

systemctl daemon-reload
systemctl enable vncserver@1
systemctl start  vncserver@1

echo "=== Bootstrap complete ==="
echo ""
echo "VNC connect: <elastic-ip>:5901"
echo ""
echo "SSM shell:   aws ssm start-session --target INSTANCE_ID --profile personal"
