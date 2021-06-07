# Canary SRV Example

This directory includes yaml for a headless service for the ingress canary
to test out SRV records as a part of [Bug 1966116](https://bugzilla.redhat.com/show_bug.cgi?id=1966116).

# Sample commands:

1. `oc project openshift-ingress-canary`
1. `oc apply -f headless-canary-service.yaml`
1. `make image`
1. `docker tag canary-srv-resolver <your-repo>`
1. `docker push <your-repo>`
1. `kubectl create deployment dns-resolver --image=<your-repo>`
1. `oc logs dns-resolver-foobar-xxxx`
