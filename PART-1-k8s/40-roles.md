# Roles & RoleBindings (RBAC)

**Learning objective:** grant least-privilege permissions and verify them with `auth can-i`.

"By default a ServiceAccount can do almost nothing. Good — that's least privilege. To let it read Pods and nothing else, you write a Role and bind it.
Let's grant exactly that and prove the boundaries."

## Demo

1. "Apply a ServiceAccount + a pod-reader Role + a RoleBinding."
   ```bash
   cat 00-manifests/rbac.yaml
   kubectl apply -f 00-manifests/rbac.yaml
   ```
   Expected: SA, Role, RoleBinding created.

2. "Test what the SA can do with `auth can-i --as`."
   ```bash
   SA=system:serviceaccount:default:pod-reader-sa
   kubectl auth can-i get pods --as=$SA          # yes
   kubectl auth can-i delete pods --as=$SA       # no
   kubectl auth can-i create deployments --as=$SA # no
   ```
   Expected: `yes`, `no`, `no` — exactly the granted verbs.

3. "The Role is namespaced — it grants nothing in other namespaces."
   ```bash
   kubectl auth can-i list pods -n kube-system --as=$SA
   ```
   Expected: `no`.

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/rbac.yaml
   ```

**✅ Conclusions:**

- Role = allowed verbs on resources (namespaced); RoleBinding grants it to a subject.
- Default is deny; you add exactly what's needed (least privilege).
- `kubectl auth can-i ... --as=` tests permissions. Next: cluster-wide RBAC.