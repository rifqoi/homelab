# Route by JSON request body (`channel`)

Goal: send `{"channel":"web"}` to `web-svc` and `{"channel":"mobile"}`
to `mobile-svc` without a separate processing service. These are design
examples, **not deployed manifests**. Replace the namespace, host, Service
names, ports, and fallback behavior for the application.

The shared gateway here runs open-source, Envoy-based kgateway 2.4.7. Gateway
API `HTTPRoute` cannot match JSON body fields directly. The Enterprise and
Envoy OSS approaches below extract `channel` into an internal header and
**clear Envoy's route cache** so the final backend decision uses that header.
The agentgateway alternative transforms the header *before* route selection.
A plain OSS `TrafficPolicy` transformation can extract the field, but does not
expose the required `clearRouteCache` setting; do not use it alone for
body-based routing.

## Common HTTPRoute

Put all rules in one HTTPRoute so an initial fallback route exists before the
body is read. The fallback below sends unknown/missing channels to `web-svc`;
change this if that is not acceptable. The policy/filter must run on requests
that initially match **any** of these rules, not just the fallback.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: channel-route
  namespace: example
spec:
  parentRefs:
    - name: shared
      namespace: kgateway-system
      sectionName: https
  hostnames:
    - channel.rifqoi.com
  rules:
    - matches:
        - headers:
            - name: x-internal-channel
              type: Exact
              value: mobile
      backendRefs:
        - name: mobile-svc
          port: 8080
    - matches:
        - headers:
            - name: x-internal-channel
              type: Exact
              value: web
      backendRefs:
        - name: web-svc
          port: 8080
    - backendRefs:
        - name: web-svc
          port: 8080
```

Do not trust a client-supplied `x-internal-channel`: overwrite it from the body
on every request, including requests that arrived with that header. Confirm
the body transformation and cache clear both run when a client supplies it,
even if parsing fails; otherwise strip/reject that header before route
selection. A failed transformation that leaves a spoofed header intact can
route to the wrong Service.

If unknown/missing channels must be rejected rather than reaching `web-svc`,
implement explicit rejection in the gateway filter (or change the request
contract); the fallback rule above does **not** reject them.

## Solo Enterprise for kgateway

This is **not compatible with the OSS chart installed here**. With a licensed
Enterprise installation and its CRDs, use a staged *early* transformation on
the whole HTTPRoute. The Enterprise policy's `clearRouteCache` is the key
difference from the OSS `TrafficPolicy`. The body remains unchanged.

```yaml
apiVersion: enterprisekgateway.solo.io/v1alpha1
kind: EnterpriseKgatewayTrafficPolicy
metadata:
  name: channel-from-body
  namespace: example
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: channel-route
  entTransformation:
    stages:
      early:
        requests:
          - clearRouteCache: true
            transformation:
              template:
                parseBodyBehavior: ParseAsJson
                headers:
                  x-internal-channel: '{{ channel }}'
```

Check the CRD/schema for the Enterprise version you install and test the
route-cache behavior against both backends before rollout. The Enterprise
template parses JSON by default and returns 400 on parse errors; the explicit
`ParseAsJson` makes this intentional. Define behavior for missing/non-string
`channel`, oversized requests, and clients supplying the internal header.
Avoid `postRouting`: cache clearing at that stage cannot change the backend.
Keep the policy scoped to the application's route, not the shared Gateway.

## Open-source kgateway / Envoy

**No supported kgateway CRD currently inserts this filter into kgateway's
xDS-generated HTTP listener.** The in-proxy OSS implementation is Envoy's
native `envoy.filters.http.transform` filter (available in Envoy 1.38, the
version documented for kgateway 2.4.x). It can parse a JSON body, overwrite a
header and clear the route cache without an extra network hop. This is an
**Envoy HTTP connection manager fragment**, not a Kubernetes manifest or a
`TrafficPolicy`:

```yaml
http_filters:
  - name: envoy.filters.http.transform
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.transform.v3.TransformConfig
      request_transformation:
        headers_mutations:
          - append:
              header:
                key: x-internal-channel
                value: "%REQUEST_BODY(channel)%"
              append_action: OVERWRITE_IF_EXISTS_OR_ADD
      clear_route_cache: true
  # Other applicable filters stay in their required order.
  - name: envoy.filters.http.router
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

To use this with the current managed `shared` Gateway, kgateway's xDS listener
generation would need an upstream-supported insertion point or a maintained
control-plane customization/fork. Patching the generated Envoy Deployment or
bootstrap ConfigMap does **not** insert a filter into the xDS listener.
Kgateway's documented self-managed gateway option lets you own the proxy
Deployment and bootstrap, but its generated HTTP listeners still come from
kgateway xDS; verify how to inject the filter before choosing that option.
Never directly edit the live Envoy config: reconciliation will replace it.

The deployed option is a **managed hybrid gateway** in
[`../kgateway-body-router/`](../kgateway-body-router/), reconciled by Flux.
A normal managed `body-router` Gateway gets a kgateway-generated
Deployment/Service, but `GatewayParameters.deploymentOverlay` repoints the
`envoy-config` volume at our own bootstrap ConfigMap. That bootstrap keeps
the generated pieces (node identity bound to the gateway, `xds_cluster`
with the `credential_injector` SA-JWT — the token file is shipped as a
second ConfigMap key, same as the generated one) and adds a static :443
listener holding the RBAC + transform + router filter chain. Its route
table comes from kgateway RDS for the listener's section name (`https`),
and upstreams come over CDS/EDS — so `httproute.yaml` is real, live
Gateway API config (verified end-to-end on the cluster).

Two details that mattered: `lds_config` must be **omitted** from the
bootstrap so kgateway doesn't also inject its own filter-less listeners,
and the RDS `route_config_name` is the listener **section name** (`https`)
for TLS listeners — `listener~<port>` is only used for plain HTTP chains.

### Configuration surface

The component is packaged as a local Helm chart
(`../kgateway-body-router/chart/`) applied via `helmrelease.yaml`. The
chart owns the gateway plumbing (GatewayParameters, GatewayClass, Gateway,
bootstrap ConfigMap); `chart/values.yaml` is the single edit point:

```yaml
hostname: channel.rifqoi.com
extractions:
  - body: channel          # %REQUEST_BODY(channel)%
    header: x-internal-channel
  - body: phone_number
    header: x-internal-phone-number
```

Each `extractions` entry generates **both** the transform
`headers_mutations` entry and an RBAC deny policy against client-supplied
copies of that header — add a field, get the spoof guard free.

Alongside the chart, plain manifests hold the app-side config:

- `httproute.yaml` — routing rules on the extracted headers (`Exact` and
  `RegularExpression` match types), plus per-field fallbacks
  (`x-internal-channel: .+` -> `other-svc`,
  `x-internal-phone-number: .+` -> `indosat-svc`) and a `DirectResponse`
  400 for bodies with neither field.
- `referencegrant.yaml` — permits the `kgateway-system` HTTPRoute to
  reference backend Services in `example`.
- `backend.yaml` — a `Backend` `priorityGroups` failover chain (see below).

To add a new body field: append to `values.extractions`, add match rules in
`httproute.yaml`. Bump `chart/Chart.yaml`'s `version` so Flux detects the
content change and performs a Helm upgrade.

### Per-service health failover

`channel: mobile` routes to a `priorityGroups` `Backend` (experimental
v1alpha1 API) rather than a Service directly:

- **Group 0** -> `mobile-backend` (primary; traffic only goes here when healthy)
- **Group 1** -> `other-backend` (absorbs traffic when group 0 is fully down)
- **`BackendConfigPolicy`** targeting the failover Backend supplies an
  active HTTP health check (`interval: 2s`, `unhealthyThreshold: 1`)
  that drives the failover.

Verified live: scaling `mobile-svc` to zero replicas spilled
`channel: mobile` traffic onto `other-svc` (HTTP 405 from nginx, not 503)
within seconds. `priorityGroups` is Envoy's priority-failover mechanism —
each group is a priority level; traffic spills to the next only when the
current level has no healthy endpoints. This is per-service health
failover without a mesh, an extra hop, or Enterprise.

### Limitations

- **Static filter chain, not kgateway-managed** — the :443 listener lives
  in our bootstrap ConfigMap, not in kgateway's generated xDS listener.
  kgateway policies that would land in the listener filter chain
  (TrafficPolicy timeouts, header modifiers, etc.) do **not** apply here;
  reimplement what you need in the static filters.
- **Transform filter maturity** — Envoy documents `envoy.filters.http.transform`
  as having limited production exposure and an unknown security posture.
  Buffer every request body; set body size limits appropriate to the app.
- **Missing/malformed fields** — a body that lacks every extracted field
  (or isn't JSON) produces no headers and hits the 400 `DirectResponse`
  catch-all. Single-field bodies are fine; only "neither field" fails.
- **Extraction is listener-wide** — every request on the gateway runs all
  extractions. Routing can't be made field-selective per route because
  extraction happens before route selection (it must, to inform it).
  True per-route extraction (annotation-driven like APISIX) would need the
  kgateway plugin fork.
- **TLS cert rotation needs a restart** — the wildcard secret is
  file-mounted; Envoy reads it at startup. `kubectl rollout restart
  deploy/body-router` after cert-manager rotates it.
- **Bootstrap is a snapshot of the generated format** — node identity,
  `xds_cluster` wiring, and the SDS token file are copied from kgateway
  2.4.7's generated bootstrap. Re-diff against a fresh generated
  bootstrap on every kgateway upgrade.
- **`priorityGroups` is experimental** — marked subject to breaking changes
  in v1alpha1. Expect the shape to move on upgrades.
- **Failover detection latency** — the health-check interval/thresholds in
  `BackendConfigPolicy` control how fast a dead service fails over; a few
  seconds of 503s is possible during detection. Tune for your SLA.
- **`httproute.yaml` header fallbacks are value fallbacks, not health
  fallbacks** — `channel: anything -> other` is a static match fallback;
  only `priorityGroups` responds to *health*.
- **Flux only sees chart-version bumps** — editing `chart/values.yaml`
  alone doesn't change the chart digest in some Flux paths; bump
  `Chart.yaml` `version` when shipping values changes so the HelmRelease
  upgrades.
- **Spoofing requires the RBAC guard** — without it a client could send
  `x-internal-channel`/`x-internal-phone-number` directly and skip the
  body entirely; keep both lists in sync by only ever adding headers via
  `extractions`, never by hand.

Envoy documents this transform filter as having limited production exposure
and an unknown security posture. Verify the exact proxy image includes it,
test JSON parse errors, empty/missing values, spoofed headers, buffering limits
and body passthrough. In particular, fail closed or remove untrusted routing
headers if the JSON cannot be parsed. Keep the filter scoped to this
application's traffic.
Do not add the fragment to the shared listener without considering other apps
(websockets, streaming uploads and non-JSON requests).

## Supported OSS alternative: agentgateway

If changing the gateway implementation is acceptable, **agentgateway** has a
documented, in-proxy, configuration-only body-routing feature. It is open
source, but it is **not** the Envoy-based kgateway 2.4.7 currently installed
here. Since kgateway 2.3, agentgateway uses a separate controller and chart;
install it and attach the common HTTPRoute above to a new Gateway with
`gatewayClassName: agentgateway`. Keep the new Gateway and this policy in the
same namespace, and change the route's `parentRefs` to that Gateway. Do not
point an `AgentgatewayPolicy` at the existing `shared` kgateway Gateway.

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: channel-from-body
  namespace: example
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: channel-gateway
  traffic:
    phase: PreRouting
    transformation:
      request:
        set:
          - name: x-internal-channel
            value: 'json(request.body).channel'
```

`PreRouting` **must target the Gateway**, not the HTTPRoute: it runs before
header-based matching. Restrict the new Gateway to this application if other
traffic is non-JSON or streams request bodies. The `json()` expression requires
valid JSON; check how the installed version handles parse errors and missing
fields, and reject or strip client-supplied routing headers when extraction
fails. Validate TLS, timeouts and existing kgateway policies separately before
migrating traffic; this is not a drop-in switch for the shared Gateway.

## Verification

After deploying in a test environment, check `HTTPRoute` and policy conditions,
then send requests to both Services (substitute the agentgateway test host if
using that alternative):

```sh
curl -i https://channel.rifqoi.com/ -H 'content-type: application/json' \
  -d '{"channel":"web"}'
curl -i https://channel.rifqoi.com/ -H 'content-type: application/json' \
  -d '{"channel":"mobile"}'
curl -i https://channel.rifqoi.com/ -H 'content-type: application/json' \
  -H 'x-internal-channel: mobile' -d '{"channel":"web"}'
```

Confirm the third request reaches **web**, not mobile, using backend logs or
distinct test responses. Also test missing/unknown `channel`, malformed JSON,
large bodies, and non-JSON requests. Whole-body buffering can increase latency
and memory usage; set and test size limits appropriate to the application.

References:

- [Gateway API / kgateway request matching](https://kgateway.dev/docs/envoy/latest/traffic-management/match/)
- [Solo Enterprise staged transformations](https://docs.solo.io/kgateway/2.3.x/traffic-management/transformations/staged/overview/)
- [Solo Enterprise template and JSON parsing](https://docs.solo.io/kgateway/2.3.x/traffic-management/transformations/staged/templating-language/)
- [Envoy 1.38 transform filter](https://www.envoyproxy.io/docs/envoy/v1.38.0/configuration/http/http_filters/transform_filter)
- [Kgateway 2.4 version matrix](https://kgateway.dev/docs/envoy/latest/reference/versions/)
- [Kgateway self-managed gateways](https://kgateway.dev/docs/envoy/latest/setup/customize/envoy/selfmanaged/)
- [Kgateway custom bootstrap scope](https://kgateway.dev/docs/envoy/latest/setup/customize/envoy/custom-bootstrap/)
- [Upstream kgateway discussion of body routing and route-cache clearing](https://github.com/kgateway-dev/kgateway/issues/11026)
- [Agentgateway native content-based routing](https://agentgateway.dev/docs/kubernetes/latest/llm/content-routing/)
- [Kgateway and agentgateway controller split](https://github.com/kgateway-dev/kgateway/blob/main/README.md)
