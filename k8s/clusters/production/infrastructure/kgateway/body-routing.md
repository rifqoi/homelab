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

The deployed option is a **hybrid self-managed gateway** in
[`../kgateway-body-router/`](../kgateway-body-router/), reconciled by Flux:
a selfManaged `body-router` Gateway whose `HTTPRoute`s kgateway translates
into RDS/CDS/EDS as usual, while a custom Envoy proxy holds a static
listener with the RBAC + transform filters and pulls that route config via
xDS (`route_config_name: listener~443`, `kgateway.kgateway-system:9977`).
So routes, header matches, and backend Services are managed in
`httproute.yaml` like any other app — only the filter chain is static.

Trade-offs: kgateway policies (TrafficPolicy/ListenerPolicy timeouts,
header modifiers) don't apply since those live in the generated filter
chain; the `listener~<port>` RDS name must be re-verified on kgateway
upgrades; and the Deployment needs a restart after cert-manager rotates
the wildcard secret (cert files are only re-read at startup). An
[isolated prototype](examples/body-routing/README.md) is kept for local
experiments; the Flux component is the version to edit.

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
