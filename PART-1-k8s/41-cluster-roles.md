# ClusterRoles & ClusterRoleBindings 

**Learning objective:** grant cluster-wide permissions with ClusterRole + ClusterRoleBinding.

"Roles stop at a namespace boundary. But some resources — nodes, PersistentVolumes — aren't in any namespace, and some permissions should span all namespaces. That's what ClusterRoles are for."

## Demo

1. "Apply a ClusterRole that can read nodes, bound cluster-wide."
   ```bash
   cat 00-manifests/clusterrole.yaml
   kubectl apply -f 00-manifests/clusterrole.yaml
   ```
   Expected: ClusterRole + ClusterRoleBinding + SA created.

2. "The SA can now list nodes — a cluster-scoped resource."
   ```bash
   SA=system:serviceaccount:default:node-viewer-sa
   kubectl auth can-i list nodes --as=$SA        # yes
   kubectl auth can-i delete nodes --as=$SA      # no
   ```
   Expected: `yes` then `no`.

3. "But only what's granted — it still can't read Pods."
   ```bash
   kubectl auth can-i get pods --as=$SA
   ```
   Expected: `no`.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/clusterrole.yaml
   ```

**✅ Conclusions:**

- ClusterRole = cluster-scoped permissions (nodes/PVs or all-namespace access).
- ClusterRoleBinding grants it cluster-wide.
- Reuse a ClusterRole in one namespace via a RoleBinding. Next: Ingress.