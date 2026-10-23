# LoadBalancer (+ kind notes)

**Learning objective:** understand the LoadBalancer type and how to reach it on kind.

"In the cloud, one line — `type: LoadBalancer` — gets you a public IP in front of your app. Let's see what that line does, and how to make it work locally on kind where there's no cloud."

## Demo

1. "Apply a LoadBalancer Service."
   ```bash
   kubectl apply -f 00-manifests/vietvn-lb.yaml
   kubectl get svc vietvn-lb
   ```
   Expected: `TYPE LoadBalancer`; `EXTERNAL-IP <pending>` on kind.

2. "Why pending? No cloud controller. Two local options:"
   ```bash
   # Option A: port-forward (simplest for local dev)
   kubectl port-forward svc/vietvn-lb 8080:80 &
   sleep 2
   curl -s localhost:8080; echo
   kill %1
   ```
   Expected: `hello from vietvn-...`.

3. "Option B (mention): `cloud-provider-kind` — a small binary that assigns
   EXTERNAL-IPs to LoadBalancer Services on kind. Great for demoing the real type."

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/vietvn-lb.yaml

**✅ Conclusions:**

- LoadBalancer = cloud LB + external IP, built on NodePort + ClusterIP.
- On kind it stays pending; use port-forward or cloud-provider-kind.
- We'll expose HTTP apps more cleanly with Ingress. Next: DNS.