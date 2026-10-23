# Annotations vs Labels

**Learning objective:** choose between labels and annotations correctly.

"Not every piece of metadata should be a label. Put the wrong thing in a label and you pollute your selectors. Enter annotations."

1. "Add annotations to a Pod."
   ```bash
   kubectl annotate pod web-prod-stable owner="team-shop" note="canary rollout 2026-10"
   kubectl get pod web-prod-stable -o jsonpath='{.metadata.annotations.owner} / {.metadata.annotations.note}'; echo
   ```
   Expected: `team-shop / canary rollout 2026-10`.

2. "Prove you CANNOT select on annotations."
   ```bash
   kubectl get pods -l 'owner=team-shop'
   ```
   Expected: `No resources found` — annotations aren't selectable.

3. "Kubernetes itself uses annotations — look at change-cause support."
   ```bash
   kubectl get pod web-prod-stable -o jsonpath='{.metadata.annotations}'; echo
   ```
   Expected: the annotations map.

**✅ Conclusions:**

- Label = identifying + selectable
- annotation = everything else.
- You can't `-l` on an annotation.
- Next section: ConfigMaps & Secrets — feeding configuration into Pods.