# homelab

NixOS and Kubernetes config for a single-server homelab. The host, the
router, and the cluster all live here: `hosts/` and `modules/` build the
NixOS machines and the nixos-containers on them, `k8s/` defines the Talos
cluster that runs on the host's libvirt, and Flux reconciles
`k8s/clusters/production` from `main`.

```text
                ┌─────────────────────────────────┐
                │  OpenWrt router · 192.168.11.1  │
                │  dewclaw config · DHCP + DNS    │
                └───────────────┬─────────────────┘
                                │ eno2: vlan30 + vlan31
┌───────────────────────────────┴──────────────────────────────────┐
│                    atlas · NixOS · ZFS rpool                     │
│  br30 = 192.168.30.101 (host)     br31 = 192.168.31.0/24         │
│                                                                  │
│  nixos-containers            host services                       │
│   garage-s3  .31.10           prometheus · grafana · ping-exp    │
│   blocky-dns .31.11           iscsi-target :3260 → rpool zvols   │
│   grafana    .31.12           libvirtd + KSM                     │
│   pocket-id  .31.13               ▲                              │
│   registry   .31.14               │ libvirt socket               │
│   omni       .31.20 ──────────────┘                              │
│   nginx      .31.30 ← *.rifqoi.com proxy + ACME (dns-01)         │
│                                                                  │
│        omni provisions Talos VMs on br31 ───┐                    │
└─────────────────────────────────────────────┼────────────────────┘
                                              │
        ┌─────────────────────────────────────▼────────────────┐
        │  talos-prod-cluster · k8s v1.35 · Talos v1.12        │
        │  1 control plane .31.200 + 4 workers · Cilium 1.18   │
        │  Flux ← git main: k8s/clusters/production            │
        │  kgateway *.rifqoi.com → external-dns → router DNS   │
        │  democratic-csi → iSCSI → atlas zvols                │
        │  vmagent → vmsingle ← atlas grafana                  │
        └──────────────────────────────────────────────────────┘
```

## Repo map

- `flake.nix`: `nixosConfigurations` for `atlas` (x86_64, the server) and
  `vm` (aarch64 test box), a deploy-rs node for atlas, the dev shell, and
  apps wrapping the iSCSI recovery scripts.
- `hosts/atlas`: the server. VLANs 30/31 on `eno2`, `br30` for the host and
  `br31` for containers and VMs, libvirtd, the iSCSI target, Prometheus and
  Grafana, plus the e1000e transmit-stall watchdog (TSO off + network-setup
  restart, 5 min cooldown).
- `hosts/openwrt`: router config as Nix, built by dewclaw.
- `modules/`: feature-flagged modules under `features.*`. `container/`
  declares every nixos-container on `br31` with its IP and its
  `*.rifqoi.com` DNS records; a path unit watches `/run/current-system` and
  upserts those records into the router over the LuCI RPC on each rebuild.
  `storage/iscsi.nix` runs targetcli for democratic-csi, backs up
  `saveconfig.json` hourly, restores it before `iscsi-target` starts, and
  autostarts the Talos VMs only after iSCSI is up.
- `grafana/`: dashboard JSONs provisioned into Grafana.
- `k8s/omni`: cluster template and libvirt machine classes. One control
  plane (`192.168.31.200`) and four workers, `qemu-guest-agent` +
  `iscsi-tools` extensions, apiserver OIDC against pocket-id. Sync with
  `omnictl cluster template sync -f cluster-template.yaml` (cordon and
  drain first, see `diagnostics/`).
- `k8s/helm`: helmfile that installs Cilium (kube-proxy replacement,
  Gateway API, L2 announcements) before Flux exists.
- `k8s/clusters/production`: the FluxInstance plus two Flux Kustomizations:
  `infrastructure` (kgateway, cert-manager, cloudnative-pg, democratic-csi,
  external-dns, VictoriaMetrics stack, ARC) and `apps`, which `dependsOn`
  infrastructure. CR instances that need operator CRDs are split into a
  `monitoring-instances` Kustomization gated on `monitoring` being Ready.
- `diagnostics/`: runbooks for failures that already happened: iSCSI target
  loss after reboot, dangling PVCs, cluster template sync loops, and the
  Disko/ZFS mount ordering rule.
- `secrets/` and `*.enc.yaml`: sops/age. Root `.sops.yaml` covers the NixOS
  host and container secrets (three keys: workstation, atlas, atlas
  containers). `k8s/clusters/production/.sops.yaml` covers Flux manifests
  decrypted in-cluster by `sops-age`.

## Common operations

```text
nix develop                        # dev shell: talosctl, omnictl, kubectl,
                                   # helmfile, flux, sops, cilium-cli, ...
deploy .#atlas                     # deploy-rs to atlas (magic rollback on)
nix run .#build-atlas              # same thing via the flake app
nix run .#packages.x86_64-linux.openwrt.targets.router   # push router config
omnictl cluster template sync -f k8s/omni/cluster-templates/cluster-template.yaml
helmfile -f k8s/helm/helmfile.yaml sync   # Cilium bootstrap only
nix run .#fix-iscsi-target -- atlas <pvc-uuid>            # see diagnostics/
```

Per-component docs that go deeper than this file:

- `k8s/clusters/production/infrastructure/kgateway/README.md`: the shared
  `*.rifqoi.com` Gateway, the cutover outage postmortem, and the checklist
  for moving an app off Cilium Ingress.
- `k8s/clusters/production/infrastructure/kgateway/body-routing.md`:
  request-body routing options (Enterprise, OSS/Envoy, agentgateway).
- `k8s/clusters/production/apps/paseo/README.md`: the Paseo deployment,
  image automation, and agent profiles.
