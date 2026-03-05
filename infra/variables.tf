variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "healthmetrics-openclaw"
}

# ── VPC ────────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.1.0.0/24"
}

variable "availability_zone" {
  description = "AZ for the public subnet"
  type        = string
  default     = "us-west-2a"
}

# ── EC2 ────────────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type. t3.small (2 vCPU/2 GiB) is the minimum usable size for OpenClaw."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 20
}

# ── OpenClaw ──────────────────────────────────────────────────────────────────

variable "openclaw_version" {
  description = "npm dist-tag or exact version to install, e.g. 'latest', 'beta', '2026.3.2'"
  type        = string
  default     = "latest"
}

# variable "openclaw_gateway_password" {
#   description = "Password for the OpenClaw gateway WebUI"
#   type        = string
#   sensitive   = true
# }

# variable "openclaw_ai_api_key" {
#   description = "AI provider API key (e.g. OpenAI sk-...). Leave empty to configure later via the WebUI."
#   type        = string
#   sensitive   = true
#   default     = ""
# }

variable "vnc_allowed_cidr" {
  description = "Source CIDR allowed to reach VNC (port 5901). Set to your public IP as /32."
  type        = string
  default     = null
}

variable "vnc_password" {
  description = "Password for the VNC server (min 6 chars, max 8 chars enforced by TigerVNC)."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Extra tags to apply to all resources"
  type        = map(string)
  default     = {}
}
