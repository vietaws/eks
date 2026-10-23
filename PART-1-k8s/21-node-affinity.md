# Node Affinity

**Learning objective:** use required vs preferred node affinity for flexible placement.

"nodeSelector is all-or-nothing. Node affinity is the grown-up version: express 'MUST be on a general node' and 'PREFER an SSD node' in the same rule. Let's use both."

## Demo

1. "Our Deployment requires node-pool=general and prefers disktype=ssd."
   ```bash
   cat 00-manifests/affinity-web.yaml
   kubectl label node k8s-course-worker disktype=ssd --overwrite
   kubectl apply -f 00-manifests/affinity-web.yaml
   kubectl rollout status deploy/affinity-web
   ```
   Expected: 3 Pods scheduled on the workers (the general pool).

2. "The preferred SSD rule pulls them toward the ssd worker."
   ```bash
   kubectl get pods -l app=affinity-web -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
   ```
   Expected: a bias toward `k8s-course-worker` (has disktype=ssd).

3. "Required is a hard filter — control-plane (not in pool) is never chosen."
   Expected: no Pods on the control-plane node.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/affinity-web.yaml
   kubectl label node k8s-course-worker disktype-
   ```

**✅ Consclutions:**

- Node affinity = nodeSelector + operators + soft preferences.
- `required` filters (hard); `preferred` scores (soft, weighted).
- Next: affinity relative to *other Pods* — pod (anti-)affinity.