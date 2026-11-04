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
expose the required `clearRouteCache` setting; the deployed
[`../kgateway-body-router/`](../kgateway-body-router/) setup therefore runs a
patched build of kgateway's rustformation dynamic module that clears the
route cache after every request transformation (see below).

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

The deployed option is a **fully managed gateway** in
[`../kgateway-body-router/`](../kgateway-body-router/), reconciled by Flux.
A dedicated `body-router` GatewayClass carries `GatewayParameters` that swap
the envoy container image for `registry.rifqoi.com/envoywrapper` — upstream
`envoy-wrapper` with a patched `librust_module.so` (built in
`rifqoi/images` `envoywrapper/`). kgateway's built-in `rustformation`
dynamic module — the one that powers `TrafficPolicy`
`transformation` — is patched to call `clear_route_cache` after a request
transformation, so headers set from the JSON body re-trigger route
selection. Everything else is stock kgateway: generated bootstrap,
listeners, SDS/TLS, and policy attachment.

A chart-generated `TrafficPolicy` `body-extract` targets the `channel-route`
HTTPRoute and sets one internal header per `values.extractions` entry using
`transformation.request.set` with `body.parseAs: AsJson`. Because the policy
targets the HTTPRoute, **per-route extraction is now possible**: each
HTTPRoute can carry its own TrafficPolicy with its own field set. One
caveat: the policy config is resolved from the route matched *before* the
body is read, so routes sharing a hostname/path prefix all start from the
same initial match — only the header re-match differs.

### Configuration surface

The component is packaged as a local Helm chart
(`../kgateway-body-router/chart/`) applied via `helmrelease.yaml`. The
chart owns the gateway plumbing (GatewayParameters, GatewayClass, Gateway,
extraction TrafficPolicy); `chart/values.yaml` is the single edit point:

```yaml
hostname: channel.rifqoi.com
image:
  registry: registry.rifqoi.com
  repository: envoywrapper
  tag: main-...               # managed by Flux image automation
extractions:
  - body: channel             # template: {{ channel }}
    header: x-internal-channel
  - body: phone_number        # template: {{ phone_number }}
    header: x-internal-phone-number
```

Each `extractions` entry generates a `transformation.request.set` entry on
the TrafficPolicy. `body` is a dotted path into the parsed JSON body;
`template` optionally overrides the whole generated template. A `set`
entry always either overwrites the header with the rendered value or
removes it on empty/failed render, and non-JSON bodies fail the
transformation with a 400 — so client-supplied copies of the internal
headers cannot spoof routing; no separate RBAC guard is needed.

Alongside the chart, plain manifests hold the app-side config:

- `httproute.yaml` — routing rules on the extracted headers (`Exact` and
  `RegularExpression` match types), plus per-field fallbacks
  (`x-internal-channel: .+` -> `other-svc`,
  `x-internal-phone-number: .+` -> `indosat-svc`) and a `DirectResponse`
  400 for bodies with neither field.
- `redirectroute.yaml` — HTTP -> HTTPS redirect on the :80 listener.
- `referencegrant.yaml` — permits the `kgateway-system` HTTPRoute to
  reference backend Services in `example`.
- `backend.yaml` — a `Backend` `priorityGroups` failover chain (see below).
- `image-automation.yaml` — `ImageRepository`/`ImagePolicy`/
  `ImageUpdateAutomation` tracking `registry.rifqoi.com/envoywrapper`
  `main-*` tags into the `chart/values.yaml` tag marker.

To add a new body field: append to `values.extractions`, add match rules in
`httproute.yaml`. The HelmRelease uses `reconcileStrategy: Revision`, so
values/template changes trigger an upgrade on the next source revision —
no `Chart.yaml` version bump needed (though the chart version is still
bumped on notable changes).

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

- **Forked dynamic module** — `librust_module.so` is patched in
  `rifqoi/images` `envoywrapper/` and must be rebased on every kgateway
  upgrade; its ABI must match the Envoy version shipped in the upstream
  `envoy-wrapper` image for that kgateway release. Treat kgateway bumps as
  blocked on a new envoywrapper build.
- **Route cache cleared on every transformed request** — the patched module
  clears the route cache after each request transformation, so every
  request on this gateway pays a second route-table lookup. Cheap, but not
  free; it is scoped to the `body-router` GatewayClass, not the shared
  gateway.
- **Image is body-router only** — the patched image is pinned on the
  `body-router` GatewayClass' GatewayParameters; the `kgateway` class keeps
  running the upstream envoy-wrapper and stock transformation semantics.
- **Body buffering** — extracting fields requires buffering the whole
  request body before forwarding. Non-JSON bodies fail the transform with
  a 400 before route selection. Set body size limits appropriate to the
  app; streaming/upload traffic does not belong on this gateway.
- **Missing fields** — a JSON body that lacks an extracted field renders
  empty, the `set` removes the internal header, and the request hits the
  `DirectResponse` catch-all. Single-field bodies are fine; only "neither
  field" fails.
- **Initial match precedes extraction** — which TrafficPolicy (and route
  timeouts/retries/etc.) applies is decided by the route matched *before*
  the body is read. Routes sharing a hostname/path prefix all start from
  the same initial match; only the header re-match after extraction
  differs.
- **`priorityGroups` is experimental** — marked subject to breaking changes
  in v1alpha1. Expect the shape to move on upgrades.
- **Failover detection latency** — the health-check interval/thresholds in
  `BackendConfigPolicy` control how fast a dead service fails over; a few
  seconds of 503s is possible during detection. Tune for your SLA.
- **`httproute.yaml` header fallbacks are value fallbacks, not health
  fallbacks** — `channel: anything -> other` is a static match fallback;
  only `priorityGroups` responds to *health*.
- **Template syntax assumed** — extraction templates are generated as
  `{{ <dotted.path> }}` against the parsed JSON body (top-level fields are
  injected into the template context by the module). Confirm against the
  patched image and adjust `extractions[].template` overrides or the
  chart template if the module expects a different accessor.

Body-based routing still buffers and parses every request body on this
gateway. Test JSON parse errors, empty/missing values, spoofed headers,
buffering limits and body passthrough before rollout, and keep the
policy scoped to this application's routes. Do not point body-dependent
routes at the shared gateway — it runs the stock module without the
route-cache clear, so extracted headers would never reach route selection.

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
