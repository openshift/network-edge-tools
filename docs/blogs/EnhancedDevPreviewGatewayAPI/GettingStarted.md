# Getting Started

In this section, we will show you how to install and configure Gateway API via the Ingress Operator. We will configure
a simple HTTPRoute and backend to demo basic Gateway API functionality.

Note: Since this is still a Developer Preview, it is important to note that it may not be flawless, and it is possible
for bugs to be present.

## Prerequisites

* A non-production OpenShift Cluster, version 4.13.5 or greater, on a cloud platform that supports Kubernetes service
  load balancers (e.g. GCP, AWS, and Azure)
* If OSSM is already installed, it must be OSSM 2.4.0
* If OSSM is already installed, you must not have any existing ServiceMeshControlPlane CRs
* The [OpenShift CLI](https://docs.openshift.com/container-platform/4.13/cli_reference/openshift_cli/getting-started-cli.html#cli-installing-cli_cli-developer-commands) binary (oc)

## Installation via the Ingress Operator
To install Gateway API using the Ingress Operator, you will do the following:
1. Grant the Ingress Operator the cluster-admin role
2. Enable the feature gate
3. Create a GatewayClass with the controller name “openshift.io/gateway-controller”

Let’s walk through each of these steps in more detail.

First, grant the Ingress Operator the cluster-admin role. This role is required in order for the Ingress Operator to
create the SMCP CR for OSSM:
```console
$ oc adm policy add-cluster-role-to-user cluster-admin -z ingress-operator -n openshift-ingress-operator
clusterrole.rbac.authorization.k8s.io/cluster-admin added: "ingress-operator"
```
It is anticipated that this need for cluster-admin permissions will be eliminated in a future release of Gateway API in
OpenShift.

Enable the feature gate for Gateway API. This will instruct the cluster Ingress Operator to install the Gateway API CRDs.
Please note that, since feature gates are stored in the machine config, patching the feature gate config will result in
the machine config operator rebooting each node sequentially, according to your machine config pool configuration:
```console
$ oc patch featuregates/cluster --type=merge --patch='{"spec":{"featureSet":"CustomNoUpgrade","customNoUpgrade":{"enabled":["GatewayAPI"]}}}'
featuregate.config.openshift.io/cluster patched
```

Wait for the ingress operator to successfully install the Gateway API CRDs:
```console
$ oc get crd gatewayclasses.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io gateways.gateway.networking.k8s.io referencegrants.gateway.networking.k8s.io
NAME                                       CREATED AT
gatewayclasses.gateway.networking.k8s.io   2023-04-04T18:02:55
httproutes.gateway.networking.k8s.io        2023-04-04T18:02:55Z
gateways.gateway.networking.k8s.io          2023-04-04T18:02:55Z
referencegrants.gateway.networking.k8s.io   2023-04-04T18:02:56Z
```

Next, create the GatewayClass with the controller name "openshift.io/gateway-controller". This will instruct the Ingress Operator to install OSSM and configure it:
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

Behind the scenes, the Ingress Operator creates a ServiceMeshControlPlane (SMCP) CR, which is the configuration API for
OSSM. Wait a minute or two for the SMCP to be created and become ready:
```console
$ oc get smcp -n openshift-ingress
NAME                READY   STATUS            PROFILES      VERSION   AGE
openshift-gateway   5/5     ComponentsReady   ["default"]   2.4.0     107s
```

OSSM will create two new Istio deployments in the `openshift-ingress` namespace. Ensure the pods for the deployments are running. These will need to become ready for the SMCP to also go ready:
```console
$ oc get deployment -n openshift-ingress
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
istio-ingressgateway       1/1     1            1           42s
istiod-openshift-gateway   1/1     1            1           55s
router-default             2/2     2            2           6h4m
```

Gateway API and OSSM have been installed successfully and are ready to use. We are now ready to create Gateways and HTTPRoutes.

## Gateway API Example

Let’s now use Gateway API to create a Gateway and Route. In this example, we will convert a simple HTTP OpenShift Route
into roughly equivalent Gateway API objects (a Gateway and an HTTPRoute). This is the OpenShift Route that we will
convert:
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

First, create the Gateway with a listener (`spec.listeners` instance) that will listen on a port for HTTP requests that
match a subdomain of the cluster domain. The Gateway must be created in the `openshift-ingress` namespace and specify
the GatewayClass that we created earlier in the `spec.gatewayClassName` field.
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
```console
$ oc get deployment -n openshift-ingress demo-gateway
NAME           READY   UP-TO-DATE   AVAILABLE   AGE
demo-gateway   1/1     1            1           25s

$ oc get service -n openshift-ingress demo-gateway
NAME           TYPE           CLUSTER-IP       EXTERNAL-IP                          PORT(S)                        AGE
demo-gateway   LoadBalancer   172.30.175.176   domain.us-east-1.elb.amazonaws.com   15021:30608/TCP,80:31833/TCP   47s
```

When the Gateway from the previous step is created, the Ingress Operator will automatically create a DNSRecord CR with
the hostname from the listener. With the DNSRecord CR created, the Ingress Operator will now create a DNS record using
the cloud-specific API (for example, Route 53 on AWS) and update the status on the DNSRecord CR accordingly:
```console
$ oc get dnsrecord -n openshift-ingress -l istio.io/gateway-name=demo-gateway -o yaml
kind: DNSRecord
metadata:
  name: gateway-7b49f58c6-wildcard
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
```console
$ oc wait -n openshift-ingress --for=condition=ready gateways.gateway.networking.k8s.io demo-gateway
gateway.gateway.networking.k8s.io/demo-gateway condition met
```

Now let’s send a request to the HTTPRoute we just created using an HTTP HEAD request to only get the headers. The `app` response header should have a value of "foo" for our demo application. You may have to wait a couple of minutes for the new DNS record to propagate before resolving:
```console
$ curl -I http://demo.gwapi.${DOMAIN}
```
You should see a 200 response code:
```
HTTP/1.1 200 OK
server: istio-envoy
app: foo
...
```

Thanks for trying OpenShift Istio Gateway API. If you'd like to learn more, go to section on [Getting Creative](./GettingCreative.md).