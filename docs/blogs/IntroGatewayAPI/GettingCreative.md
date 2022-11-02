# Getting Creative

In the previous section, we showed how to create a simple HTTPRoute. Let’s expand upon this example and include more
advanced usages of Gateway API.

## Configuring DNS

If you would like the example routes to work in your browser instead of using `curl`, you will need to create a DNS record,
point it to `INGRESS_HOST`, and configure the HTTPRoute’s `spec.hostnames` and the Gateway’s `spec.listeners[].hostname`
to support the new domain name:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
...
spec:
gatewayClassName: istio
listeners:
- name: demo
  hostname: "*.<DOMAIN_NAME>" #[1]
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
...
spec:
parentRefs:
- name: gateway
  namespace: demo-gateway
  hostnames: ["http.<DOMAIN_NAME>"] #[2]
```
[1]: Specify a wildcard with your new domain name.\
[2]: Specify the `http` subdomain with your new domain name.

## Route Matching
Gateway API has a powerful API for directing traffic based on request characteristics such as path, headers, query
parameters, and HTTP methods. Let’s explore how we can use these functions to direct traffic to different backends.

#### Path Based Routing
In this first example, we will match traffic based on the paths `/foo` and `/bar`. Path-based routing is useful for
segmenting a website into various backend services. In the current OpenShift Route API, we must make a Route per path:
```yaml
apiVersion: v1
kind: Route
metadata:
  name: http-foo
  namespace: demo-app
spec:
  host: www.http.example.com
  to:
    kind: Service
    name: foo-app
  port:
    targetPort: 8080
  path: /foo
---
apiVersion: v1
kind: Route
metadata:
  name: http-bar
  namespace: demo-app
spec:
  host: www.http.example.com
  to:
    kind: Service
    name: bar-app
  port:
    targetPort: 8080
  path: /bar
```

However, Gateway API enables the path-based matching to be declared in a single HTTPRoute object as we will demonstrate
in this example.

First, let’s create another demo application deployment and service using `oc new-app`, our `cakephp-ingress-demo`
project, and the `bar` git branch. This will be used as an alternate server backend, `bar-app`, to direct traffic to:
```shell
$ oc new-app -n demo-app --name bar-app https://github.com/openshiftdemos/cakephp-ingress-demo#bar
$ oc rollout status deployment -w -n demo-app bar-app
```

Next, let’s modify our existing HTTPRoute to direct traffic based on path. We will add a `/foo` path match on the
existing rule for the `foo-app` application as well as a new rule with a `/bar` path match and a backendRef pointing to the
`bar-app` application:
```yaml
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: http
  namespace: demo-app
spec:
  parentRefs:
  - name: gateway
    namespace: demo-gateway
  hostnames: ["http.example.com"]
  rules:
  - matches: #[1]
    - path:
        type: Exact
        value: /foo
    backendRefs:
    - name: foo-app
      port: 8080
  - matches: #[2]
    - path:
        type: Exact
        value: /bar
    backendRefs:
    - name: bar-app
      port: 8080
EOF
```
[1] `/foo` path match on the existing rule for the `foo-app` application.\
[2] new rule with a `/bar` path match and a backendRef pointing to the `bar-app` application.

Now let’s test our path-based routing configuration:
```shell
$ curl -sH "Host: http.example.com" $INGRESS_HOST/foo
Welcome to the foo application!

$ curl -sH "Host: http.example.com" $INGRESS_HOST/bar
Welcome to the bar application!
```

### Other Matching Functions
Gateway API offers additional ways of routing traffic. Besides matching on path, Gateway API also allows you to match
requests based on HTTP headers, URL query parameters, and HTTP method. Currently, the OpenShift Route API does not offer
a way to match traffic on any of these options.

The `headers` match rule can be used to match on custom headers or on standard HTTP headers. For example, a rule could
match on the `accept-encoding` header in order to use a different backend for clients requesting HTML and clients requesting
json. Similarly, `queryParams` can match on arbitrary URL query parameters.

The following example shows header and URL query parameter matching. First, we set a match rule using `queryParams` that
if the `app` query parameter is set to `foo`, the request should be forwarded to the `foo-app` application; and second, we
set a match rule using headers that if the `x-app` header is set to `bar`, the request should be forwarded to the `bar-app`
application:
```yaml
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: http
  namespace: demo-app
spec:
  parentRefs:
  - name: gateway
    namespace: demo-gateway
  hostnames: ["http.example.com"]
  rules:
  - matches:
    - queryParams: #[1]
      - name: app
        value: foo
    backendRefs:
    - name: foo-app
      port: 8080
  - matches:
    - headers: #[2]
      - name: x-app
        value: bar 
    backendRefs:
    - name: bar-app
      port: 8080
EOF

```
[1] `queryParams`: if the `app` query parameter is set to `foo`, the request should be forwarded to the `foo-app` application.\
[2] `headers`: if the `x-app` header is set to `bar`, the request should be forwarded to the `bar-app` application.

Now let’s test query parameter matching:
```shell
$ curl -sH "Host: http.example.com" $INGRESS_HOST?app=foo
Welcome to the foo application!
```

Next, let's test header matching:
```shell
$ curl -sH "Host: http.example.com" -H "x-app: bar" $INGRESS_HOST
Welcome to the bar application!
```

You’ve successfully configured Gateway API to match traffic based on path, query parameters, and headers.

## TLS Termination with Gateway API
In OpenShift, we have the concept of [termination types](https://docs.openshift.com/container-platform/4.11/networking/routes/secured-routes.html) 
to achieve different forms of secured routing. In this example, we will explore how to create an edge terminated route with Gateway API.

An edge route in OpenShift terminates TLS encryption at the Ingress Controller before forwarding traffic to the
destination pod:
```yaml
apiVersion: v1
kind: Route
metadata:
  name: http-foo
  namespace: demo-app
spec:
  host: www.edge.example.com
  to:
    kind: Service
    name: foo-app
  port:
    targetPort: 8080
tls:
  termination: edge
  insecureEdgeTerminationPolicy: Redirect
  certificate: <CERT>
  key: <KEY>
path: /foo
```
In Gateway API, we can translate this concept to terminating the TLS encryption at Gateway before forwarding traffic to
the HTTPRoute.

First, we will need a certificate for configuring the TLS termination. Acquire a certificate with the common name that
you want to use from your CA.  

For testing purposes, you can create your own CA and serving certificate as follows:
```
$ mkdir certs
$ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=MyCompany/CN=example.com' -keyout certs/ca.key -out certs/ca.crt
$ openssl req -out certs/edge.csr -newkey rsa:2048 -nodes -keyout certs/edge.key -subj "/CN=*.example.com/O=MyCompany"
$ openssl x509 -req -sha256 -days 365 -CA certs/ca.crt -CAkey certs/ca.key -set_serial 0 -in certs/edge.csr -out certs/edge.crt
```

Add the certificate as a secret in the `demo-gateway` namespace:
```shell
$ oc create -n demo-gateway secret tls edge-cert --key=certs/edge.key --cert=certs/edge.crt
```
Certificates are handled differently in Gateway API compared to OpenShift Route objects. Gateway API uses references to
Kubernetes Secret objects whereas the OpenShift Route API embeds the certificate and key strings in the Route object.

Next, let’s configure our Gateway to terminate TLS. We will add an additional Listener with the same wildcard domain
using port 443 to our existing Gateway from the example above:
```yaml
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: gateway
  namespace: demo-gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    hostname: "*.example.com"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: edge
    hostname: "*.example.com"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: edge-cert
    allowedRoutes:
      namespaces:
        from: All
EOF
```
Next, let’s create the HTTPRoute that will route our TLS terminated connection to the backend:
```yaml
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: edge
  namespace: demo-app
spec:
  parentRefs:
  - name: gateway
    namespace: demo-gateway
  hostnames: ["edge.example.com"]
  rules:
  - backendRefs:
    - name: foo-app
      port: 8080
EOF
```
Now test the route we just created over port 443. Using the `curl --resolve` feature requires `INGRESS_HOST` to be an IP.
We will create `INGRESS_HOST_IP` for platforms that use a hostname for the external IP (you won’t need to do this if
`INGRESS_HOST` is already an IP):
```shell
$ INGRESS_HOST=$(oc get gateways.gateway.networking.k8s.io gateway -n demo-gateway -ojsonpath='{.status.addresses[*].value}')
$ INGRESS_HOST_IP=$(dig +short $INGRESS_HOST | head -1)
$ curl -I --resolve "edge.example.com:443:$INGRESS_HOST_IP" -H "Host: edge.example.com" --cacert certs/ca.crt https://edge.example.com:443
HTTP/1.1 200 OK
server: istio-envoy
app: foo
...
```
You have successfully configured Gateway API to use encrypted traffic to the Gateway.
