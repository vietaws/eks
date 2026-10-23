# Headless Services & Identity

**Learning objective:** use a headless Service to address individual StatefulSet Pods by DNS.

"A normal Service hides Pods behind one load-balanced IP. But a database replica needs to reach `web-0` *specifically*. A headless Service gives each Pod its own
DNS name."

## Demo

1. "Our StatefulSet's Service is headless."
   ```bash
   kubectl get svc web-hl
   ```
   Expected: `CLUSTER-IP  None`.

2. "Resolve an individual Pod by its stable DNS name."
   ```bash
   kubectl run dns --image=busybox:1.36 --restart=Never -i --rm -- \
     nslookup web-0.web-hl.default.svc.cluster.local
   ```
   Expected: resolves to web-0's Pod IP.

3. "The headless Service returns ALL Pod IPs (not one VIP)."
   ```bash
   kubectl run dns --image=busybox:1.36 --restart=Never -i --rm -- \
     nslookup web-hl.default.svc.cluster.local
   ```
   Expected: multiple A records — one per Pod.

**✅ Conclusions:**

- `clusterIP: None` = headless; DNS returns Pods directly, no load-balancing.
- StatefulSet + headless Service = stable per-Pod DNS (`web-0.web-hl`).
- That's the identity backbone for databases and clustered systems.