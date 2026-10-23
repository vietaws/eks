# Endpoints: How Services Find Pods

**Learning objective:** explain how a Service's selector becomes a live list of ready Pod IPs.

"A Service load-balances to Pods — but how does it *know* which Pods, and how does it drop a sick one? The answer is EndpointSlices. Let's watch them update in real time."

## Demo

1. "Show the Service's endpoints — these are the Pod IPs behind it."
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=vietvn
   kubectl get endpointslices -l kubernetes.io/service-name=vietvn \
     -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
   ```
   Expected: 3 Pod IPs listed.

2. "Scale the backend and watch the endpoint list grow."
   ```bash
   kubectl scale deploy/vietvn --replicas=5
   kubectl wait --for=jsonpath='{.status.readyReplicas}'=5 deploy/echo --timeout=60s
   kubectl get endpointslices -l kubernetes.io/service-name=vietvn \
     -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\n"}{end}'
   ```
   Expected: now 5 Pod IPs.

3. "A Service with a selector that matches nothing has no endpoints — a common 'my Service returns nothing' bug."
   ```bash
   kubectl get endpointslices -l kubernetes.io/service-name=vietvn -o jsonpath='{.items[0].endpoints[*].conditions.ready}'; echo
   ```
   Expected: `true true true true true` — all ready.

4. "Clean up the section."
   ```bash
   kubectl delete -f 00-manifests/vietvn-clusterip.yaml
   ```

**✅ Conclusions:**

- Selector → EndpointSlice (ready Pod IPs) → kube-proxy routing.
- Only ready Pods receive traffic; readiness probes gate membership.
- Empty endpoints = selector/label mismatch — your #1 Service debugging check.