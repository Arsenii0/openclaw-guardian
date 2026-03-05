# OpenClaw

Self-hosted AI assistant gateway on EC2.
Secure AWS Terraform deployment for OpenClaw.

---

## Deploy

```bash
# 1. Set secrets in infra/terraform.tfvars
# TODO ArsenP : use secret manager
# openclaw_gateway_password = "TODO_secretmanager1"
# openclaw_ai_api_key       = "TODO_secretmanager2" 

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
```

To connect with VNC use `<elastic-ip>:5900`

---

## Security notes

TODO ArsenP
