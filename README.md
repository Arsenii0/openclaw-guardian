# OpenClaw

Self-hosted AI assistant gateway on EC2.
Secure AWS Terraform deployment for OpenClaw.

---

## Deploy

```bash
# 1. Set secrets in infra/terraform.tfvars
# TODO ArsenP : use secret manager
openclaw_gateway_password = "TODO_secretmanager1"
openclaw_ai_api_key       = "TODO_secretmanager2" 

# 2. Start the deployment container
./deploy.sh

# 3. Inside the deployment container, run Terraform
terraform init && terraform apply
```

---

## Connect

```bash
# Shell
aws ssm start-session --target <instance_id> --region us-west-2

# WebUI (then open http://localhost:18789)
aws ssm start-session --target <instance_id> --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters 'portNumber=18789,localPortNumber=18789'
```

`instance_id` → `terraform output instance_id`

---

## Check health

```bash
sudo systemctl status openclaw-gateway
sudo -u openclaw openclaw doctor
```

---

## Security notes

- Zero inbound ports — SSM only (outbound HTTPS)
- Secrets embedded in user_data (`sensitive = true`), stored in `/etc/openclaw/secrets.env` (mode 600)
- IMDSv2 required, hop limit 1 (blocks container escapes)
- OpenClaw runs as unprivileged `openclaw` user
- Gateway bound to loopback only (port 18789)
- EBS encrypted with KMS, rotation enabled
