# Getting Started

In this section, we will show you how to install and configure Gateway API via the Ingress Operator. We will configure a simple HTTPRoute and backend to demo basic Gateway API functionality.

Note: Gateway API via Ingress Operator is GA in OpenShift 4.19.  These instructions were originally written for the Developer Preview (prior to OpenShift 4.19).  They should work on GA versions as well; where there are differences, they are noted below.
## Prerequisites

  * Prior to GA 4.19, use a non-production OpenShift Cluster
  * OpenShift version 4.18 or greater, on a cloud platform that supports Kubernetes service load balancers (e.g. GCP, AWS, and Azure)
  * If OSSM is already installed, the minimum required version is:
    * OSSM 2.6 for OpenShift 4.18
    * OSSM 3.0.1 for OpenShift 4.19
    * OSSM 3.1.0 for OpenShift 4.20
  * In OpenShift 4.18, if OSSM is already installed, you must not have any existing ServiceMeshControlPlane CRs
  * The [OpenShift CLI](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/cli_tools/openshift-cli-oc) binary (`oc`)

-----

## Installation via the Ingress Operator

To install Gateway API using the Ingress Operator:

* **OCP 4.19 and later:** Create a GatewayClass with controller name `openshift.io/gateway-controller/v1` (see [Step 3](#3-create-the-gatewayclass))
* **OCP versions before 4.19:** Follow Steps 1-3 below (grant cluster-admin role, enable the `GatewayAPI` feature gate, create GatewayClass)

### 1\. Grant Cluster-Admin Role (For OCP version before 4.19)

  * **OpenShift 4.19 and beyond:** This step is no longer required and should be skipped.

First, grant the Ingress Operator the cluster-admin role. This role is required in order for the Ingress Operator to create the SMCP CR for OSSM:


```console
$ oc adm policy add-cluster-role-to-user cluster-admin -z ingress-operator -n openshift-ingress-operator
clusterrole.rbac.authorization.k8s.io/cluster-admin added: "ingress-operator"
```

### 2\. Enable the Feature Gate (For OCP version before 4.19)

  * **OpenShift 4.19 and beyond:** This step is no longer required and should be skipped.

Enable the feature gate for Gateway API. This will instruct the cluster Ingress Operator to install the Gateway API CRDs.
Please note that, since feature gates are stored in the machine config, patching the feature gate config will result in the machine config operator rebooting each node sequentially, according to your machine config pool configuration:

```console
$ oc patch featuregates/cluster --type=merge --patch='{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["GatewayAPI"]}}}'
featuregate.config.openshift.io/cluster patched
```

Wait for the ingress operator to successfully install the Gateway API CRDs:

> **Note:** OCP 4.19 and later also includes the `grpcroutes.gateway.networking.k8s.io` CRD for routing gRPC traffic.

```console
$ oc get crd gatewayclasses.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io gateways.gateway.networking.k8s.io referencegrants.gateway.networking.k8s.io
NAME                                        CREATED AT
gatewayclasses.gateway.networking.k8s.io    2025-02-04T10:49:54Z
httproutes.gateway.networking.k8s.io        2025-02-04T10:49:55Z
gateways.gateway.networking.k8s.io          2025-02-04T10:49:54Z
referencegrants.gateway.networking.k8s.io   2025-02-04T10:49:55Z
```

### 3\. Create the GatewayClass

Next, create the GatewayClass. The controller name differs by version:

  * **Prior to OpenShift 4.19:** Use controller name `openshift.io/gateway-controller`
    ```console
    $ oc create -f -<<'EOF'
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: GatewayClass
    metadata:
      name: openshift-default
    spec:
      controllerName: openshift.io/gateway-controller
    EOF
    gatewayclass.gateway.networking.k8s.io/openshift-default created
    ```

  * **OpenShift 4.19 and beyond:** Use controller name `openshift.io/gateway-controller/v1`
    ```console
    $ oc create -f -<<'EOF'
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: openshift-default
    spec:
      controllerName: openshift.io/gateway-controller/v1
    EOF
    gatewayclass.gateway.networking.k8s.io/openshift-default created
    ```

Behind the scenes, the Ingress Operator sets up OSSM. The mechanism differs by version: prior to 4.19 it creates a ServiceMeshControlPlane (SMCP) CR; in 4.19 it creates an Istio CR; in 4.20 and later OSSM is installed without OLM and no SMCP or Istio CR is created. Wait a minute or two for setup to complete:

  * **Prior to OpenShift 4.19:** OSSM uses ServiceMeshControlPlane (SMCP) resources.
    ```console
    $ oc get smcp -n openshift-ingress
    NAME                READY   STATUS            PROFILES      VERSION   AGE
    openshift-gateway   5/5     ComponentsReady   ["default"]   2.4.0     10m
    ```

  * **OpenShift 4.19:** OSSM 3 uses Istio resources instead of SMCP.
    ```console
    $ oc get istio -A
    NAME                NAMESPACE           PROFILE   REVISIONS   READY   IN USE   ACTIVE REVISION     STATUS    VERSION   AGE
    openshift-gateway   openshift-ingress             1           1       0        openshift-gateway   Healthy   v1.26.2   2m
    ```

  * **OpenShift 4.20 and beyond:** OSSM is installed without OLM — no SMCP or Istio CR is created. Verify by checking the deployment instead (see below).

OSSM will create Istio deployments in the `openshift-ingress` namespace. Ensure the pods for the deployments are running.

  * **Prior to OpenShift 4.19:** OSSM creates a shared `istio-ingressgateway` deployment and the control plane.
    ```console
    $ oc get deployment -n openshift-ingress
    NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
    istio-ingressgateway      1/1     1            1           42s
    istiod-openshift-gateway  1/1     1            1           55s
    router-default            2/2     2            2           6h4m
    ```

  * **OpenShift 4.19 and beyond:** Only the Istio control plane (`istiod`) is created at this stage. Individual gateway deployments are created when you create Gateway resources.
    ```console
    $ oc get deployment -n openshift-ingress
    NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
    istiod-openshift-gateway   1/1     1            1           2m
    router-default             2/2     2            2           6h4m
    ```

  * **OpenShift 4.20 and beyond (NO-OLM):** Same result — only the Istio control plane is created at this stage, but without OLM-managed resources.
    ```console
    $ oc -n openshift-ingress get deployment
    NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
    istiod-openshift-gateway   1/1     1            1           55s
    ```

Gateway API and OSSM have been installed successfully and are ready to use. We are now ready to create Gateways and HTTPRoutes.

-----

## Gateway API Example

Let’s now use Gateway API to create a Gateway and Route. In this example, we will convert a simple HTTP OpenShift Route into roughly equivalent Gateway API objects (a Gateway and an HTTPRoute). This is the OpenShift Route that we will convert:

```yaml
apiVersion: v1
kind: Route
metadata:
  name: http
  namespace: demo-app
spec:
  host: demo.${DOMAIN}
  to:
    kind: Service
    name: foo-app
  port:
    targetPort: 8080
```

First, create the Gateway with a listener (`spec.listeners` instance) that will listen on a port for HTTP requests that match a subdomain of the cluster domain. The Gateway must be created in the `openshift-ingress` namespace and specify the GatewayClass that we created earlier in the `spec.gatewayClassName` field.

```console
$ DOMAIN=$(oc get ingresses.config/cluster -o jsonpath={.spec.domain})
$ oc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: openshift-ingress
spec:
  gatewayClassName: openshift-default
  listeners:
  - name: demo
    hostname: "*.gwapi.${DOMAIN}"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF
gateway.gateway.networking.k8s.io/demo-gateway created
```

By default, Istio will [automatically provision](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/#automated-deployment) a gateway deployment and service with the same name upon creation of this Gateway object:

* **OpenShift 4.19 and beyond:** The deployment name changes to `demo-gateway-openshift-default`.


```console
$ oc get deployment -n openshift-ingress demo-gateway-openshift-default
NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
demo-gateway-openshift-default  1/1     1            1           25s

$ oc get service -n openshift-ingress demo-gateway-openshift-default
NAME                            TYPE          CLUSTER-IP       EXTERNAL-IP                          PORT(S)                        AGE
demo-gateway-openshift-default  LoadBalancer  172.30.175.176   domain.us-east-1.elb.amazonaws.com   15021:30608/TCP,80:31833/TCP   47s
```

When the Gateway from the previous step is created, the Ingress Operator will automatically create a DNSRecord CR with the hostname from the listener. With the DNSRecord CR created, the Ingress Operator will now create a DNS record using the cloud-specific API (for example, Route 53 on AWS) and update the status on the DNSRecord CR accordingly:

```console
$ oc get dnsrecord -n openshift-ingress
NAME                               AGE
demo-gateway-86888cb7cc-wildcard   5m

$ oc get dnsrecord -n openshift-ingress demo-gateway-86888cb7cc-wildcard -o yaml
kind: DNSRecord
metadata:
  name: demo-gateway-86888cb7cc-wildcard
  namespace: openshift-ingress
  [...]
spec:
  dnsName: '*.gwapi.${DOMAIN}.'
  targets:
  - domain.us-east-1.elb.amazonaws.com
  [...]
status:
  [...]
  zones:
  - conditions:
    - message: The DNS provider succeeded in ensuring the record
      reason: ProviderSuccess
      status: "True"
      type: Published
    dnsZone:
      tags:
        [...]
  - conditions:
    - message: The DNS provider succeeded in ensuring the record
      reason: ProviderSuccess
      status: "True"
      type: Published
    dnsZone:
      id: [...]
```

Next, let’s create and configure a namespace called "demo-app" that will have our HTTPRoute object and our example application:

```console
$ oc create namespace demo-app
namespace/demo-app created
```

Create a demo application deployment and service using the `oc new-app` command and the `foo` branch of our `cakephp-ingress-demo` GitHub project. This will create a simple server, foo-app, that will allow us to test connectivity. Then use the `oc rollout` command to wait for it to be rolled out:

```console
$ oc new-app -n demo-app --name foo-app https://github.com/openshiftdemos/cakephp-ingress-demo#foo
--> Found image 3c92c13 (13 days old) in image stream "openshift/php" under tag "8.0-ubi8" for "php"

    Apache 2.4 with PHP 8.0
    -----------------------
    PHP 8.0 available as container is a base platform for building and running various PHP 8.0 applications and frameworks. PHP is an HTML-embedded scripting language. PHP attempts to make it easy for developers to write dynamically generated web pages. PHP also offers built-in database integration for several commercial and non-commercial database management systems, so writing a database-enabled webpage with PHP is fairly simple. The most common use of PHP coding is probably as a replacement for CGI scripts.

    Tags: builder, php, php80, php-80

    * The source repository appears to match: php
    * A source build using source code from https://github.com/openshiftdemos/cakephp-ingress-demo#foo will be created
      * The resulting image will be pushed to image stream tag "foo-app:latest"
      * Use 'oc start-build' to trigger a new build

--> Creating resources ...
    imagestream.image.openshift.io "foo-app" created
    buildconfig.build.openshift.io "foo-app" created
    deployment.apps "foo-app" created
    service "foo-app" created
--> Success
    Build scheduled, use 'oc logs -f buildconfig/foo-app' to track its progress.
    Application is not exposed. You can expose services to the outside world by executing one or more of the commands below:
      'oc expose service/foo-app'
    Run 'oc status' to view your app.

$ oc rollout status deployment -w -n demo-app foo-app
deployment "foo-app" successfully rolled out
```

Create the HTTPRoute CR that will direct requests for `demo.gwapi.${DOMAIN}` to our new foo-app application. Note that the `parentRefs` field points to the Gateway, `rules` specifies `backendRefs` pointing to our service, and `hostnames` specifies a host name that matches the Gateway’s listener's wildcard host name:

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
  hostnames: ["demo.gwapi.${DOMAIN}"]
  rules:
  - backendRefs:
    - name: foo-app
      port: 8080
EOF
httproute.gateway.networking.k8s.io/http created
```

Wait for the gateway deployment to be ready:

  * **Prior to OpenShift 4.19:** The condition is `Ready`.
    ```console
    $ oc wait -n openshift-ingress --for=condition=ready gateways.gateway.networking.k8s.io demo-gateway
    ```
  * **OpenShift 4.19 and beyond:** The condition is `Programmed`.
    ```console
    $ oc wait -n openshift-ingress --for=condition=programmed gateways.gateway.networking.k8s.io demo-gateway
    gateway.gateway.networking.k8s.io/demo-gateway condition met
    ```

Now let’s send a request to the HTTPRoute we just created using an HTTP HEAD request to only get the headers. The `app` response header should have a value of "foo" for our demo application. You may have to wait a couple of minutes for the new DNS record to propagate before resolving:

```console
$ curl -I http://demo.gwapi.${DOMAIN}
```

You should see a 200 response code. The response will include headers from the application:

  * **Prior to OpenShift 4.19:** Response includes `istio-envoy` server header.
    ```
    HTTP/1.1 200 OK
    server: istio-envoy
    app: foo
    ...
    ```

  * **OpenShift 4.19 and beyond:** The `istio-envoy` server header is no longer included. The response shows the application's own server header instead.
    ```
    HTTP/1.1 200 OK
    date: Wed, 05 Nov 2025 15:58:06 GMT
    server: Apache/2.4.62 (Red Hat Enterprise Linux) OpenSSL/3.2.2
    content-type: text/html; charset=UTF-8
    app: foo
    ...
    ```

Thanks for trying OpenShift Istio Gateway API. If you'd like to learn more, go to section on [Getting Creative](./GettingCreative.md).