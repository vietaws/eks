# Service Discovery & DNS

**Learning objective:** resolve Services by DNS name and understand the naming scheme.

"How does one microservice find another? Not by IP — by name. Kubernetes runs its own DNS so `http://echo` just works. Let's prove it."

## Demo

1. "Our echo Service exists. Resolve its name from a throwaway Pod."
   ```bash
   kubectl run dnsjob --image=busybox:1.36 --restart=Never -i --rm -- \
     nslookup echo
   ```
   Expected: resolves to the Service's ClusterIP.

2. "The fully-qualified name works too."
   ```bash
   kubectl run dnsjob --image=busybox:1.36 --restart=Never -i --rm -- \
     nslookup echo.default.svc.cluster.local
   ```
   Expected: same ClusterIP.

3. "And you can just curl by name — DNS + Service together."
   ```bash
   kubectl run curljob --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- \
     curl -s http://echo
   ```
   Expected: `hello from echo-...`.

4. "Who serves this? CoreDNS in kube-system."
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```
   Expected: CoreDNS Pods Running.

**✅ Conclusions:**

- Service DNS = `<service>.<namespace>.svc.cluster.local`.
- Same namespace -> short name; CoreDNS does the resolving.
- Next: what actually links a Service to its Pods — Endpoints.