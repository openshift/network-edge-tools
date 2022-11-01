# Getting Started

In this section, we will show you how to install and configure Gateway API and Istio Ingress alongside OpenShift’s
existing route ingress. We will configure a simple HTTPRoute and backend to demo basic Gateway API functionality.

## Prerequisites

* A non-production OpenShift v4.12 Cluster on a cloud platform that supports Kubernetes external load balancers.
  * If you have a non-cloud platform such as bare metal, you will need to configure a manual gateway deployment with
    `hostNetwork: true` or `hostPort` along with an appropriate bare metal ingress solution such as MetalLB.
* The [OpenShift CLI](https://docs.openshift.com/container-platform/4.11/cli_reference/openshift_cli/getting-started-cli.html#cli-installing-cli_cli-developer-commands)
  binary (oc)

> Note: This has not been tested for compatibility with the Istio installation from the OpenShift Service Mesh.

## Installation
First, install the Gateway API CRDs. For this tutorial, we are going to use Gateway API v1beta1 provided by version 0.5.1:
```shell
$ oc kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.5.1" | oc apply -f -;
```
By default, OpenShift only allows containers to use a pre-allocated list of UIDs, but Istio will use a UID
outside this range. We need to allow the `istio-system` namespace use any UID:
```shell
$ oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-system
```
Next, configure, download, and install the appropriate version of Istio. We will use the `minimal` profile since
Gateway API Ingress only needs a minimal set of Istio features to be functional:
``` shell
$ export ISTIO_VERSION=1.15.1
$ wget https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz
$ tar xzvf istio-${ISTIO_VERSION}-linux-amd64.tar.gz
$ cd istio-${ISTIO_VERSION}
$ export PATH=$PWD/bin:$PATH
$ istioctl install --set profile=minimal -y --set meshConfig.accessLogFile=/dev/stdout
```
Ensure that istio was installed successfully:
```shell 
$ istioctl verify-install
```

Look for the last line, which should say: `Istio is installed and verified successfully`

You’ve successfully installed and configured Gateway API and Istio. We are now ready to create Gateways and HTTPRoutes.

## Gateway API Example

Let’s now use Gateway API to create a Gateway and Route. In this example, we will convert a simple HTTP OpenShift Route into
roughly equivalent Gateway API objects:

```yaml
apiVersion: v1
kind: Route
metadata:
  name: http
  namespace: demo-app
spec:
  host: www.http.example.com
  to:
    kind: Service
    name: foo-app
  port:
    targetPort: 8080
```

First, let’s create and configure a namespace called `demo-gateway` that will have our Gateway deployment and service.
This namespace will also need the `anyuid` scc to allow the gateway deployment (Envoy) to function:
```yaml
$ oc create namespace demo-gateway
$ oc adm policy add-scc-to-group anyuid system:serviceaccounts:demo-gateway
```

Create the Gateway with a Listener that will listen for requests to `*.example.com`. By default, Istio will [automatically
provision](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/#automated-deployment) a gateway
deployment and service with the same name upon creation of this Gateway object:
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
  - name: demo
    hostname: "*.example.com"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF
```

Next, let’s create and configure a namespace called `demo-app` that will have our HTTPRoute object and our example application:
```shell
$ oc create namespace demo-app
```

Create a demo application deployment and service using `oc new-app`, our `cakephp-ingress-demo` project, and the `foo`
git branch. This will create a simple server, `foo-app`, that will allow us to test connectivity. Then use the `oc rollout`
command to wait for it to be rolled out:
```shell
$ oc new-app -n demo-app --name foo-app https://github.com/openshiftdemos/cakephp-ingress-demo#foo
$ oc rollout status deployment -w -n demo-app foo-app
```

Create the HTTPRoute that will direct requests for `http.example.com` to our new backend server, `foo-app`:
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
  - backendRefs:
    - name: foo-app
      port: 8080
EOF
```

Wait for the gateway deployment (Envoy) to be ready. Then set the ingress host variable `INGRESS_HOST` to the external
load balancer hostname or IP:
```shell
$ oc wait -n demo-gateway --for=condition=ready gateways.gateway.networking.k8s.io gateway
$ export INGRESS_HOST=$(oc get gateways.gateway.networking.k8s.io gateway -n demo-gateway -ojsonpath='{.status.addresses[*].value}')
```

Now let’s curl the route we just created using an HTTP Head request to only get the headers. The `app` response header
should have a value of `foo` for our demo application. You may have to wait a couple minutes for DNS if your platform
uses a domain name for the service’s External IP:
```shell
$ curl -I -H "Host: http.example.com" $INGRESS_HOST
```

You should see a 200 response code:
```shell
HTTP/1.1 200 OK
server: istio-envoy
app: foo
...
```
