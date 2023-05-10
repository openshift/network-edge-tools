# Getting Creative

In the previous section, we showed how to create a simple HTTPRoute. Let’s expand upon this example and include more
advanced usages of Gateway API.

## Route Matching
Gateway API is a powerful API for directing traffic based on request characteristics such as path, headers, query
parameters, and HTTP methods. Let’s explore how we can use these functions to direct traffic to different backends.

#### Path Based Routing
In this first example, we will match traffic based on the paths `/foo` and `/bar`. Path-based routing is useful for
segmenting a website into various backend services. In the current OpenShift Route API, we must make a route per path:
```yaml
apiVersion: v1
kind: Route
metadata:
  name: http-foo
  namespace: demo-app
spec:
  host: http.${DOMAIN}
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
  host: http.${DOMAIN}
  to:
    kind: Service
    name: bar-app
  port:
    targetPort: 8080
  path: /bar
```

However, Gateway API enables the path-based matching to be declared in a single HTTPRoute object as we will demonstrate
in this example.

First, let’s create another demo application deployment and service using the `oc new-app` command and the `bar` branch
of our `cakephp-ingress-demo` GitHub project. This will be used as an alternate server backend, `bar-app`, to direct
traffic to:
```console
$ oc new-app -n demo-app --name bar-app https://github.com/openshiftdemos/cakephp-ingress-demo#bar
--> Found image 3c92c13 (13 days old) in image stream "openshift/php" under tag "8.0-ubi8" for "php"

    Apache 2.4 with PHP 8.0
    -----------------------
    PHP 8.0 available as container is a base platform for building and running various PHP 8.0 applications and frameworks. PHP is an HTML-embedded scripting language. PHP attempts to make it easy for developers to write dynamically generated web pages. PHP also offers built-in database integration for several commercial and non-commercial database management systems, so writing a database-enabled webpage with PHP is fairly simple. The most common use of PHP coding is probably as a replacement for CGI scripts.

    Tags: builder, php, php80, php-80

    * The source repository appears to match: php
    * A source build using source code from https://github.com/openshiftdemos/cakephp-ingress-demo#bar will be created
      * The resulting image will be pushed to image stream tag "bar-app:latest"
      * Use 'oc start-build' to trigger a new build

--> Creating resources ...
    imagestream.image.openshift.io "bar-app" created
    buildconfig.build.openshift.io "bar-app" created
    deployment.apps "bar-app" created
    service "bar-app" created
--> Success
    Build scheduled, use 'oc logs -f buildconfig/bar-app' to track its progress.
    Application is not exposed. You can expose services to the outside world by executing one or more of the commands below:
     'oc expose service/bar-app'
    Run 'oc status' to view your app.

$ oc rollout status deployment -w -n demo-app bar-app
deployment "bar-app" successfully rolled out
```

Next, let’s modify our existing HTTPRoute to direct traffic based on path. We will add a `/foo` path match on the
existing rule for the `foo-app` application as well as a new rule with a `/bar` path match and a `backendRef` pointing to the
`bar-app` application:
```console
$ DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: http
  namespace: demo-app
spec:
  parentRefs:
  - name: demo-gateway
    namespace: openshift-ingress
  hostnames: ["http.gwapi.${DOMAIN}"]
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
httproute.gateway.networking.k8s.io/http configured
```
[1] `/foo` path match on the existing rule for the `foo-app` application.\
[2] New rule with a `/bar` path match and a backendRef pointing to the `bar-app` application.

Now let’s test our path-based routing configuration:
```console
$ curl -s http://http.gwapi.${DOMAIN}/foo
Welcome to the foo application!

$ curl -s http://http.gwapi.${DOMAIN}/bar
Welcome to the bar application!
```

### Other Matching Functions
Gateway API offers additional ways of routing traffic. Besides matching on path, Gateway API also allows you to match
requests based on HTTP headers, URL query parameters, and HTTP methods. Currently, the OpenShift Route API does not offer
a way to match traffic on any of these attributes.

The `headers` match rule can be used to match on custom headers or on standard HTTP headers. For example, a rule could
match on the `accept-encoding` header in order to use a different backend for clients requesting HTML and clients requesting
json. Similarly, `queryParams` can match on arbitrary URL query parameters.

The following example shows header and URL query parameter matching. First, we set a match rule using `queryParams` that
if the `app` query parameter is set to `foo`, the request should be forwarded to the `foo-app` application; and second, we
set a match rule using headers that if the `x-app` header is set to `bar`, the request should be forwarded to the `bar-app`
application:
```console
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: http
  namespace: demo-app
spec:
  parentRefs:
  - name: demo-gateway
    namespace: openshift-ingress
  hostnames: ["http.gwapi.${DOMAIN}"]
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
httproute.gateway.networking.k8s.io/http configured
```
[1] `queryParams`: if the `app` query parameter is set to `foo`, the request should be forwarded to the `foo-app` application.\
[2] `headers`: if the `x-app` header is set to `bar`, the request should be forwarded to the `bar-app` application.

Now let’s test query parameter matching:
```console
$ curl -s http://http.gwapi.${DOMAIN}?app=foo
Welcome to the foo application!
```

Next, let's test header matching:
```console
$ curl -sH "x-app: bar" http://http.gwapi.${DOMAIN}
Welcome to the bar application!
```

You’ve successfully configured Gateway API to match traffic based on path, query parameters, and headers.

## TLS Termination with Gateway API
In OpenShift, we have the concept of [TLS termination types](https://docs.openshift.com/container-platform/4.13/networking/routes/secured-routes.html)
to achieve different forms of secured routing. In this example, we will explore how to create an edge-terminated TLS route with Gateway API.

An edge route in OpenShift terminates TLS encryption at the Ingress Controller before forwarding traffic to the
destination pod:
```yaml
apiVersion: v1
kind: Route
metadata:
  name: http-foo
  namespace: demo-app
spec:
  host: edge.${DOMAIN}
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
In Gateway API, we can translate this concept to terminating the TLS encryption at the Gateway before forwarding traffic
to the destination pod via the HTTPRoute configuration.

First, we will need a certificate for configuring the TLS termination. Acquire a certificate with the common name that
you want to use from your CA.  

For testing purposes, you can create your own CA and serving certificate as follows:
```
$ mkdir certs
$ openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj "/O=MyCompany/CN=gwapi.${DOMAIN}" -keyout certs/ca.key -out certs/ca.crt
$ openssl req -out certs/edge.csr -newkey rsa:2048 -nodes -keyout certs/edge.key -subj "/CN=*.gwapi.${DOMAIN}/O=MyCompany"
$ openssl x509 -req -sha256 -days 365 -CA certs/ca.crt -CAkey certs/ca.key -set_serial 0 -in certs/edge.csr -out certs/edge.crt
```

Add the certificate as a Secret in the `openshift-ingress` namespace:
```console
$ oc create -n openshift-ingress secret tls edge-cert --key=certs/edge.key --cert=certs/edge.crt
secret/edge-cert created
```
Certificates are handled differently in Gateway API compared to OpenShift Route objects. Gateway API uses references to
Kubernetes Secret objects whereas the OpenShift Route API embeds the certificate and key strings in the Route object.

Next, let’s configure our Gateway to terminate TLS. We will add a listener with the same wildcard domain using port 443
to our existing Gateway from the example above:
```console
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: openshift-ingress
spec:
  gatewayClassName: openshift-default
  listeners:
  - name: http
    hostname: "*.gwapi.${DOMAIN}"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
  - name: edge
    hostname: "*.gwapi.${DOMAIN}"
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
gateway.gateway.networking.k8s.io/demo-gateway configured
```
Next, let’s create the HTTPRoute that will route our TLS terminated connection to the backend:
```console
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: edge
  namespace: demo-app
spec:
  parentRefs:
  - name: demo-gateway
    namespace: openshift-ingress
  hostnames: ["edge.gwapi.${DOMAIN}"]
  rules:
  - backendRefs:
    - name: foo-app
      port: 8080
EOF
httproute.gateway.networking.k8s.io/edge created
```
Now test the route we just created over port 443:
```console
$ curl -I --cacert certs/ca.crt https://edge.gwapi.${DOMAIN}:443
HTTP/1.1 200 OK
server: istio-envoy
app: foo
...
```
You have successfully configured Gateway API to use encrypted traffic to the Gateway.
