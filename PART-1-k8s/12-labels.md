# Labels

**Learning objective:** attach, change, and remove labels, and see why they matter.

"Labels look trivial — just key/value tags. But they're the single most important organizing idea in Kubernetes. Services, Deployments, and almost every command you run uses them. Let's get fluent."

## Demo

1. "Create a set of Pods with varied labels."
   ```bash
   kubectl apply -f 00-manifests/zoo.yaml
   kubectl get pods -L tier,env,track
   ```
   Expected: 4 Pods, label columns populated.

2. "Add or overwrite a label on a live object."
   ```bash
   kubectl label pod web-dev-stable track=experimental --overwrite
   kubectl get pod web-dev-stable -L track
   ```
   Expected: `track=experimental`.

3. "Remove a label with a trailing dash."
   ```bash
   kubectl label pod web-dev-stable track-
   kubectl get pod web-dev-stable -L track
   ```
   Expected: TRACK column now empty.

**✅ Conclusions:**

- Labels = identifying key/value metadata.
- `kubectl label ... key=value --overwrite` to set, `key-` to remove.
- Next: querying by labels with selectors.
