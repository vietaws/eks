# Selectors (Set-based)

**Learning objective:** use set-based selectors (in/notin/exists).

"Equality covers most cases, but sometimes you want 'env is dev OR prod' or 'has any track label.' That's set-based selectors."

## Demo

1. "env in a set."
   ```bash
   kubectl get pods -l 'env in (dev,prod)'
   ```
   Expected: all 4 Pods.

2. "Exclude canary, across those envs."
   ```bash
   kubectl get pods -l 'env in (dev,prod), track notin (canary)'
   ```
   Expected: 3 Pods (canary dropped).

3. "Existence check."
   ```bash
   kubectl get pods -l 'track'
   kubectl get pods -l '!track'
   ```
   Expected: `track` -> all with the label; `!track` -> none (all have it).

**✅ Conclusions:**

- `in`, `notin`, `key` (exists), `!key` (not exists).
- Backs `matchExpressions` in controllers.
- Next: annotations — metadata you *don't* select on.