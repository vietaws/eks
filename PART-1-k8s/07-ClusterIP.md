# ClusterIP (the default)

**Learning objective:** create a ClusterIP Service and prove it load-balances across Pods.

## Demo

0. "Imperative first — create and expose with two commands."
   ```bash
   kubectl create deployment vietvn --image=hashicorp/http-echo:1.0 --replicas=3 -- /http-echo -text=hi -listen=:5678
   kubectl rollout status deploy/vietvn
   kubectl expose deployment vietvn --port=80 --target-port=5678 --name=vietvn
   kubectl get svc vietvn
   ```
   Expected: a ClusterIP Service created instantly. Now the committable version (our manifest makes each Pod vietvn its own name so we can see balancing).
   ```bash
   kubectl delete deployment vietvn && kubectl delete svc vietvn
   ```

1. "Apply the backend (3 Pods) and a ClusterIP Service."
   ```bash
   kubectl apply -f 00-manifests/vietvn-clusterip.yaml
   kubectl get svc vietvn
   kubectl get endpointslices -l kubernetes.io/service-name=vietvn
   ```
   Expected: Service with a CLUSTER-IP; an EndpointSlice listing 3 Pod IPs.

2. "Call the Service by name from inside the cluster, repeatedly."
   ```bash
   kubectl run curljob --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- \
     sh -c 'for i in $(seq 1 9); do curl -s vietvn; echo; done'
   ```
   Expected: responses come from *different* Pod names — load-balancing!

3. "The Service IP is stable even as Pods churn."
   ```bash
   kubectl delete pod -l app=vietvn --field-selector=status.phase=Running | head -1
   kubectl get svc vietvn       # same CLUSTER-IP
   ```
   Expected: Pods change, CLUSTER-IP stays.


**✅ Conclusions:**

- ClusterIP = stable virtual IP + round-robin to selected Pods.
- Reach it by name (`vietvn`) thanks to cluster DNS.
- Only reachable *inside* the cluster. Next: NodePort for outside access.