# Paseo

This is the Flux-managed Paseo daemon and self-hosted web UI for the Talos
production cluster. It is one `Deployment` with `Recreate` strategy; it does
not use a `StatefulSet`.

The existing `omnigent` namespace and home claim are retained for this
in-place migration. The claim is mounted as both `/home/paseo` and
`/workspace`, so the existing Codex OAuth state, skills, MCP configuration,
and agent configuration remain available after the image switch. The legacy
Omnigent artifact PVC is retained but is no longer mounted.

Paseo's official image does not include agent CLIs. The Dockerfile lives in
the private `rifqoi/images` repo (`paseo/Dockerfile`) and adds Codex, Claude
Code, OpenCode, Devin, `oc`/`kubectl`, and the GitHub CLI. Pushing to that repo
builds `registry.rifqoi.com/paseo:main-<unix-ts>-<shortsha>` on the in-cluster
ARC runners. `image-automation.yaml` makes Flux pick the newest `main-*` tag and
commit it into the `$imagepolicy` markers in `deployment.yaml`, which rolls the
Pod. Do not edit those image tags by hand.

The GitHub CLI is not logged in by default. Log in once with OAuth; the state
lives in `/home/paseo/.config/gh` on the home volume and survives restarts. Run
it as the `paseo` user, because `kubectl exec` is root and root-owned files
under `/home/paseo` break the daemon until the next restart re-chowns them:

```text
kubectl -n omnigent exec -it deploy/paseo -c paseo -- gosu paseo gh auth login
```

The public endpoint is `https://paseo.rifqoi.com`, protected by the SOPS
encrypted `PASEO_PASSWORD` Secret. Paseo uses its own password connection;
there is no Pocket ID callback or Cloudflare dependency.

Do not commit OAuth tokens, kubeconfigs, SSH keys, or MCP bearer tokens. Keep
those in the persistent home volume or Kubernetes Secrets. Stdio MCP servers
must exist in the Paseo image and HTTP MCP servers must be reachable from the
Pod.

## Agent profiles

`agent-profiles.json` is the source of truth for Paseo's host-level
`daemon.agentProfiles`. The deployment merges it into
`/home/paseo/.paseo/config.json` before Paseo starts, preserving the rest of the
config. Edit the Git file to change profiles; UI changes will be replaced on
the next Pod restart unless copied back here.

Retrieve the generated connection password locally with:

```text
sops -d k8s/clusters/production/apps/paseo/paseo-secrets.enc.yaml
```
