# Paseo

This is the Flux-managed Paseo daemon and self-hosted web UI for the Talos
production cluster. It is one `Deployment` with `Recreate` strategy; it does
not use a `StatefulSet`.

The existing `omnigent` namespace and home claim are retained for this
in-place migration. The claim is mounted as both `/home/paseo` and
`/workspace`, so the existing Codex OAuth state, skills, MCP configuration,
and agent configuration remain available after the image switch. The legacy
Omnigent artifact PVC is retained but is no longer mounted.

Paseo's official image does not include agent CLIs. `Dockerfile` adds Codex,
Claude Code, and OpenCode; it is built on `atlas` and pushed to the private
registry as `registry.rifqoi.com/paseo:latest`.

The public endpoint is `https://paseo.rifqoi.com`, protected by the SOPS
encrypted `PASEO_PASSWORD` Secret. Paseo uses its own password connection;
there is no Pocket ID callback or Cloudflare dependency.

Do not commit OAuth tokens, kubeconfigs, SSH keys, or MCP bearer tokens. Keep
those in the persistent home volume or Kubernetes Secrets. Stdio MCP servers
must exist in the Paseo image and HTTP MCP servers must be reachable from the
Pod.

Retrieve the generated connection password locally with:

```text
sops -d k8s/clusters/production/apps/paseo/paseo-secrets.enc.yaml
```
