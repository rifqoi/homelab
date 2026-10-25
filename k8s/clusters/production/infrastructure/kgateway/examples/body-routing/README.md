# Isolated OSS body-routing proxy prototype

This example demonstrates the Envoy filter chain for routing on a JSON
`channel` value **inside the proxy**, without an ext-proc service. It is NOT
included in the production kgateway kustomization and does not change
`shared`. The `body-routing-demo` GatewayClass uses a separate
`GatewayParameters.spec.selfManaged` so the controller does not create another
proxy. This repo's Gateway API v1.0 CRDs do not support per-Gateway
`spec.infrastructure.parametersRef`.

**Important boundary:** The Envoy configuration here is static. The provided
proxy has no xDS subscription; its `Gateway` object does not supply its routes,
TLS settings or Service endpoints. In particular, attaching an `HTTPRoute` to
`body-routing-demo` will not update this listener, and the Gateway may not
report `Programmed`. This is an *unverified Envoy data-plane prototype*, not a
complete kgateway self-managed Gateway integration. A fully kgateway-managed
solution requires a control-plane extension that emits this filter in its xDS
listeners, or a supported filter insertion API if one becomes available.
Do not point external-dns or production traffic at this example. Merely
providing a custom Envoy image or bootstrap cannot alter kgateway's
xDS-generated HTTP filter chain.

## Prepare

1. Supply two HTTP Kubernetes Services on port 8080, called `web-svc` and
   `mobile-svc` in namespace `example`, or change the two DNS names and ports
   in `proxy.yaml` to match your Services. Backend hostnames are placeholders.
2. Verify the proxy image contains `envoy.filters.http.transform` and
   `envoy.filters.http.rbac`. Envoy 1.38 documents both, but this image has
   not been tested in this workspace.
3. Apply manually **only in a test cluster**:

```sh
kubectl apply -k k8s/clusters/production/infrastructure/kgateway/examples/body-routing
kubectl -n kgateway-system rollout status deploy/body-routing-demo
kubectl -n kgateway-system port-forward svc/body-routing-demo 18080:8080
```

The Envoy RBAC filter denies a client-supplied `x-internal-channel` (403).
The native transform filter buffers JSON, writes that header from
`%REQUEST_BODY(channel)%`, then clears the route cache. The fallback responds
400 for unknown/missing channels, without forwarding to either Service.

## Exercise

In another terminal:

```sh
curl -i localhost:18080 -H 'content-type: application/json' \
  -d '{"channel":"web"}'
curl -i localhost:18080 -H 'content-type: application/json' \
  -d '{"channel":"mobile"}'
curl -i localhost:18080 -H 'content-type: application/json' \
  -d '{"channel":"other"}'
curl -i localhost:18080 -H 'content-type: application/json' \
  -H 'x-internal-channel: mobile' -d '{"channel":"web"}'
curl -i localhost:18080 -H 'content-type: application/json' \
  -d '{"channel":'
```

Confirm the first two reach distinct Services (inspect backend logs), unknown
values do not reach a backend (400), and supplied routing headers are rejected
(403). Check the actual malformed JSON response and any oversized request
response before exposing the proxy. JSON buffering raises memory and latency
costs; Envoy flags the transform filter as having limited production exposure
and unknown security posture. The example is HTTP-only, ClusterIP-only, and
does not configure TLS, access policy, or production observability.

References: [kgateway self-managed proxies](https://kgateway.dev/docs/envoy/latest/setup/customize/envoy/selfmanaged/),
[Envoy 1.38 transform filter](https://www.envoyproxy.io/docs/envoy/v1.38.0/configuration/http/http_filters/transform_filter),
[Envoy RBAC filter](https://www.envoyproxy.io/docs/envoy/v1.38.0/configuration/http/http_filters/rbac_filter).
