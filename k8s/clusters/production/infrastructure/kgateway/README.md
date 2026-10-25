# kgateway

This is the shared Gateway API entrypoint for `*.rifqoi.com` on the Talos
production cluster. One `Gateway` (`kgateway-system/shared`) owns a single
LoadBalancer IP, and app `HTTPRoute`s in any namespace attach to it.

- `gateway.yaml` has two listeners: `http` on 80 and `https` on 443,
  terminating TLS with the `kgw-wildcard-tls` wildcard certificate from
  `certificate.yaml`.
- `https-redirect.yaml` is the only route on the `http` listener. It 301s every
  `*.rifqoi.com` request to HTTPS, which is the Gateway API equivalent of
  `ingress.cilium.io/force-https`. It is annotated
  `external-dns.alpha.kubernetes.io/controller: none` so external-dns does not
  publish a wildcard record.
- `gatewayparameters.yaml` adds `announce: "true"` to the generated Service.
  The `manual-announce-l2` `CiliumL2AnnouncementPolicy` selects on that label;
  without it the LB IP is never ARP-announced. It is attached to the `kgateway`
  GatewayClass through the chart value `gatewayClassParametersRefs`, because the
  installed Gateway API CRDs (v1.0.0) have no `spec.infrastructure` for a
  per-Gateway reference.

Each app needs exactly one `HTTPRoute`: `parentRefs` `shared` with
`sectionName: https`, plus its hostname in `spec.hostnames`. external-dns
publishes the hostname with the Gateway's address from `status.addresses`, and
that one record serves both ports.

The LB IP (currently `192.168.31.139`) is not pinned. Cilium LB IPAM picks it
from `libvirt-pool` (`192.168.31.128/26`), so it can change if the Service is
recreated. Set `spec.addresses` on the Gateway to pin it.

## 2026-10-24 cutover outage

After `bb42bff` removed the Cilium Ingresses for paseo, lajur-dev, ck-x, and
metamcp, all four hosts timed out. The HTTPRoutes were Accepted and Programmed
and the backends were healthy; the failure was entirely in DNS and L2. Three
independent problems stacked:

1. **external-dns crashlooped.** The kgateway POC added the `gateway-tlsroute`
   source, but the TLSRoute CRD is not installed (standard channel only, and
   v1.0.0 has no `v1` TLSRoute). external-dns exited on every start with
   `failed to sync *v1.TLSRoute after 1m0s`, so it never processed the
   HTTPRoutes. Fixed by removing the source (#15).

2. **Existing DNS records were never updated.** The OpenWrt webhook stores
   records as UCI `dhcp` `domain` entries (name and IP only), so the `txt`
   registry's ownership TXT records never persist. external-dns then treats
   every existing record as foreign and silently skips updates ("All records
   are already up to date"). Creates still work, which hid this until a
   hostname had to change IP. The old A records pointed at the deleted
   per-Ingress IPs (`.134` to `.137`). Unblocked by deleting the four
   `dhcp.@domain` entries on the router so external-dns recreated them; fixed
   for good by switching to `registry: noop` in the external-dns HelmRelease
   (#17). `policy: upsert-only` still prevents deletes.

3. **The gateway IP was not announced.** Cilium LB IPAM assigns an IP to every
   LoadBalancer Service, but L2 announcement only covers Services matched by a
   `CiliumL2AnnouncementPolicy`. Cilium labels its own Ingress Services
   `cilium.io/ingress: "true"`; the kgateway Service had no matching label, so
   no node answered ARP for `.139` and the router's neighbour entry stayed
   `FAILED`. Fixed by `gatewayparameters.yaml` (#16).

## Checklist for moving an Ingress here

1. Add the app's `HTTPRoute` on `shared/https`. Do not add a per-app redirect
   route.
2. Remove the Ingress.
3. Confirm the record moved: `dig +short @192.168.11.1 <host>` should return
   the Gateway address. If it still shows the old Ingress IP, check that
   external-dns is running and that its registry is still `noop`.
4. Confirm reachability: `curl -sI https://<host>` reaches the app and
   `curl -sI http://<host>` returns a 301.

If a host times out while DNS is correct, check the L2 side first:

```text
kubectl -n kgateway-system get svc shared --show-labels   # announce=true
kubectl -n kube-system get lease | grep kgateway-system-shared
```
