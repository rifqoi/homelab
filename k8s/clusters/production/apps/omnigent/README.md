# Omnigent

This is the Flux-managed Omnigent deployment for the production Talos
cluster. It uses the upstream server base, a single Omnigent server
`Deployment`, and one persistent registered Codex host `Deployment`.
It intentionally does not use a `StatefulSet` or build a custom image.

The server artifact database and uploaded bundles live on the upstream PVC. The
Codex host home lives on `omnigent-codex-host-home`, which preserves the local
Codex OAuth state and Omnigent host registration across Pod restarts. Omnigent
can run multiple sessions through this registered host; they share the same
Codex account and host resources.

## Required private Secret

The encrypted `omnigent-secrets.enc.yaml` file patches the upstream Secret
named `omnigent-secrets` in namespace `omnigent` with:

```text
DATABASE_URL=sqlite:////data/artifacts/chat.db
OMNIGENT_ACCOUNTS_COOKIE_SECRET=<64 hex characters>
```

The Codex OAuth state is intentionally not a Git or SOPS Secret. After the
host Pod is running, complete both interactive logins against the PVC:

```text
kubectl --context omni-talos-prod-cluster -n omnigent exec -it deploy/omnigent-codex-host -- omnigent login https://omnigent.rifqoi.com
kubectl --context omni-talos-prod-cluster -n omnigent exec -it deploy/omnigent-codex-host -- codex login --device-auth
```

The server uses Omnigent's built-in accounts provider rather than Pocket ID
OIDC. Open the web UI once to claim the instance and create the first admin,
then use that account for `omnigent login`.

The host waits for both auth files before registering itself. Do not put local
`~/.codex/auth.json`, `~/.codex/config.toml`, SSH keys, or kubeconfigs in this
repository. The OAuth files are private data on the PVC, not GitOps config.

## Private agent configuration

Keep the local agent bundle in a separate private Git repository. The bundle
should contain only portable agent material (`config.yaml`, `AGENTS.md`, and
`skills/*/SKILL.md`); keep OAuth tokens, SSH keys, and kubeconfigs out of it.
Import/update that private bundle through Omnigent's agent management flow so
the server stores the resulting bundle on its artifact PVC.
