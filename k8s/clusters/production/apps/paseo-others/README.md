# Paseo Others

This is a separate, bare Paseo daemon using the official `ghcr.io/getpaseo/paseo` image. It has its own password, home volume, workspace volume, namespace, and URL at `https://paseo-others.rifqoi.com`.

It does not mount the existing Paseo home or workspace and does not include the custom agent image, provider CLIs, skills repository, agent profiles, work secrets, image receiver, or VPN sidecar. The official image serves the web UI, but provider CLIs and credentials must be added separately before it can launch coding agents.

The generated connection password is stored in `paseo-others-secrets.enc.yaml` and can be retrieved with:

```text
sops -d k8s/clusters/production/apps/paseo-others/paseo-others-secrets.enc.yaml
```
