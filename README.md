# OpenClaw

Self-hosted AI assistant gateway on EC2.
Secure AWS Terraform deployment for OpenClaw.

---

## Deploy

```bash
# 1. Start the deployment container
./deploy.sh

# 2. Inside the deployment container, run Terraform
terraform init && terraform apply
```

---

## Connect

```bash
# Shell
aws ssm start-session --target <instance_id> --region us-west-2
```

To connect with VNC use `<elastic-ip>:5901`


## Installation
Fix OpenClaw after installation in the cloud deployment:
```
# 1. Enable persistent user services
sudo loginctl enable-linger $(whoami)

# 2. Set runtime directory (add to ~/.bashrc for persistence)
export XDG_RUNTIME_DIR=/run/user/$(id -u)

# 3. Now gateway install works
openclaw gateway install --force

openclaw doctor --repair
openclaw gateway start

```

Integrate with Telegram:
```
<start the bot in telegram>
openclaw pairing list telegram
openclaw pairing approve telegram <ID>
```


## Security notes

TODO: Bind VNC to localhost and use SSM port-forwarding instead of exposing port 5901 publicly (unencrypted, 8-char password limit).
TODO: Replace `curl | bash` Node.js install in `user_data.sh` with a distro package or pre-baked AMI to eliminate supply-chain RCE risk.
