# AI Coding Instructions

- Generate production-quality code.
- Follow HashiCorp Terraform style.
- No hardcoded secrets.
- Every module: main.tf, variables.tf, outputs.tf, README.md.
- Use Conventional Commits.
- For OCI micro instances, apply `AI_DEPLOYMENT_RUNBOOK.md` §3 (kdump/`dnf` memory
  fixes, nginx routing rules) and verify with §7; skipping them leads to
  `504 Gateway Time-out`.
- At startup, ask for a domain name for the public nginx box (`AI_DEPLOYMENT_RUNBOOK.md`
  §0.3). If the user has none, recommend a free one (e.g. DNSExit `*.publicvm.com`) and
  configure a trusted Let's Encrypt cert with `terraform/deploy/enable-letsencrypt.sh`.
  Only fall back to a self-signed cert if the user declines.
