# Omnigent

This is the Flux-managed Omnigent deployment for the production Talos
cluster. It uses the upstream Kubernetes runner overlay, a single Omnigent
server `Deployment`, and one Kubernetes `Job`/runner Pod per managed session.
It intentionally does not use a `StatefulSet` or build a custom image.

The server artifact database and uploaded bundles live on the upstream PVC. The
runner workspaces are ephemeral Job storage; server history and artifacts remain
available after a runner Pod exits. Native `agent_sandbox` PVC-backed sessions
are a later option, but require installing the agent-sandbox controller and
CRDs first.

## Required private Secret

The encrypted `omnigent-secrets.enc.yaml` file patches the upstream Secret
named `omnigent-secrets` in namespace `omnigent` with:

```text
DATABASE_URL=sqlite:////data/artifacts/chat.db
OMNIGENT_OIDC_CLIENT_ID=<Pocket ID client id>
OMNIGENT_OIDC_CLIENT_SECRET=<Pocket ID client secret>
OMNIGENT_OIDC_REDIRECT_URI=https://omnigent.rifqoi.com/auth/callback
OMNIGENT_OIDC_COOKIE_SECRET=<64 hex characters>
```

Create the separate `omnigent-creds` Secret in namespace `omnigent-sandboxes`
with only the model,
Git, and harness credentials the runners need, for example
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`,
`CODEX_ACCESS_TOKEN`, and a private Git token. Do not put local
`~/.codex/config.toml`, SSH keys, or the skills bundle in this repository.

Register the Pocket ID client with this callback before exposing the Cilium
Ingress.
The OIDC client must be separate from the Headlamp client.

## Private agent configuration

Keep the local agent bundle in a separate private Git repository. The bundle
should contain only portable agent material (`config.yaml`, `AGENTS.md`, and
`skills/*/SKILL.md`); keep API keys, OAuth tokens, SSH keys, and kubeconfigs in
the Kubernetes Secrets above. Import/update that private bundle through
Omnigent's agent management flow so the server stores the resulting bundle on
its artifact PVC.
