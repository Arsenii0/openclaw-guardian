# ─────────────────────────────────────────────────────────────────────────────
# Security Group strategy
#
#  INBOUND  – none. Gateway stays on loopback:18789; access is SSM-only.
#
#  OUTBOUND – HTTPS (443) to reach AI provider APIs, Telegram/Discord/WhatsApp,
#             AWS SSM endpoints, apt mirrors, npm registry, etc.
#           - HTTP (80) for apt and npm (redirects to HTTPS).
#           - DNS UDP/TCP 53.
#           - NTP UDP 123.
#
# The OpenClaw gateway WebSocket (18789) is intentionally NOT opened;
# you reach it via SSM port-forwarding or Tailscale Serve.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "openclaw" {
  name        = "${var.name_prefix}-sg"
  description = "OpenClaw EC2 - outbound-only, no inbound rules"
  vpc_id      = aws_vpc.openclaw.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg" })
}

# ── Inbound ──────────────────────────────────────────────────────────────────
# No inbound rules. Access is exclusively via AWS SSM Session Manager,
# which uses outbound HTTPS (443) to the SSM service — no open ports needed.

# ── Outbound ─────────────────────────────────────────────────────────────────

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.openclaw.id
  description       = "HTTPS - AI APIs, messaging platforms, SSM, npm, apt"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.openclaw.id
  description       = "HTTP - apt / npm redirects"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.openclaw.id
  description       = "DNS UDP"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.openclaw.id
  description       = "DNS TCP"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ntp" {
  security_group_id = aws_security_group.openclaw.id
  description       = "NTP"
  from_port         = 123
  to_port           = 123
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"
}
