FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.16-openshift-4.8 AS builder
WORKDIR /build
COPY . .
RUN make build

FROM centos:8
COPY --from=builder /build/resolve /usr/bin
CMD ["/usr/bin/resolve"]
