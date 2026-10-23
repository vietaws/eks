# Install metrics-server

**Learning objective:** install metrics-server on kind to enable `kubectl top` and HPA.

"`kubectl top` and autoscaling both need one thing kind doesn't ship: metrics-server. Let's install it — with the one kind-specific tweak that trips everyone up."

## Demo

1. "Install the official manifest."
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```
   Expected: metrics-server Deployment created in kube-system.

2. "Add the kind-specific flag, then wait for rollout."
   ```bash
   kubectl patch deployment metrics-server -n kube-system --type='json' \
     -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
   kubectl rollout status deployment/metrics-server -n kube-system
   ```
   Expected: rolls out successfully.

3. "Give it ~20s to collect, then `kubectl top` works."
   ```bash
   sleep 20
   kubectl top nodes
   kubectl top pods -A | head
   ```
   Expected: live CPU/memory for nodes and Pods.

**✅ Conclusions:**

- metrics-server feeds `kubectl top` and the HPA.
- On kind you must add `--kubelet-insecure-tls` (dev-only).
- Next: autoscale a Deployment with an HPA.