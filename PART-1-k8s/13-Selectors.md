# Selectors (Equality)

**Learning objective:** filter objects with equality-based selectors.

"You've got hundreds of Pods. How do you act on just the frontend ones in prod? Selectors. Let's slice our Pod zoo with simple equality queries."

## Demo

1. "All frontend Pods in prod."
   ```bash
   kubectl get pods -l 'env=prod,tier=frontend'
   ```
   Expected: `web-prod-stable`, `web-prod-canary`.

2. "Everything that is NOT canary."
   ```bash
   kubectl get pods -l 'track!=canary'
   ```
   Expected: the 3 non-canary Pods.

3. "Combine: backend Pods, any env."
   ```bash
   kubectl get pods -l 'tier=backend'
   ```
   Expected: `api-prod-stable`.

4. "Selectors drive actions, not just listing — e.g., delete a slice (don't run now): `kubectl delete pod -l track=canary`."

**✅ Conclusions:**

- `key=value`, `key!=value`, comma = AND.
- Same syntax Services use to find Pods.
- Next: set-based selectors for `in`/`notin`/`exists`.