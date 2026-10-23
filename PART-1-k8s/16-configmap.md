# ConfigMaps as Environment Variables 

**Learning objective:** create a ConfigMap and inject its keys as env vars into a Pod.

"Hardcoding config in your image means rebuilding for every environment. Bad.

ConfigMaps let you ship one image and feed it different settings. Let's wire one up as environment variables."

## ConfigMap - Env

0. "Imperative first — create a ConfigMap from literals."
   ```bash
   kubectl create configmap app-config --from-literal=APP_COLOR=blue --from-literal=APP_MODE=production
   kubectl get configmap app-config -o yaml | sed -n '1,8p'
   ```
   Expected: a ConfigMap with both keys — no file needed. Now the committable
   version, which also carries a file-style key.
   ```bash
   kubectl delete configmap app-config
   ```

1. "Create the ConfigMap from the manifest."
   ```bash
   kubectl apply -f 00-manifests/app-config.yaml
   kubectl get configmap app-config -o yaml | sed -n '1,12p'
   ```
   Expected: data keys `APP_COLOR`, `APP_MODE`, `app.properties`.

2. "A Pod pulls two keys in as env vars."
   ```bash
   kubectl apply -f 00-manifests/cm-env-demo.yaml
   kubectl wait --for=condition=Ready pod/cm-env-demo --timeout=60s
   kubectl logs cm-env-demo
   ```
   Expected: `COLOR=blue MODE=production`.

3. "Confirm from inside the container."
   ```bash
   kubectl exec cm-env-demo -- printenv APP_COLOR APP_MODE
   ```
   Expected: `blue` and `production`.

4. "Clean up the Pod (keep the ConfigMap for the next lesson)."
   ```bash
   kubectl delete pod cm-env-demo
   ```

**✅ Conclusions:**

- ConfigMap = external key/value config.
- `configMapKeyRef` injects a key as an env var.
- Next: mount a ConfigMap as files for config that belongs on disk.

## ConfigMap Files

**Learning objective:** mount a ConfigMap as a volume so keys appear as files.

"Some apps want a config *file*, not env vars — nginx.conf, application.yaml.
ConfigMaps do that too: mount them and each key becomes a file."

1. "Reuse the ConfigMap; this Pod mounts it at /etc/appconfig."
   ```bash
   cat 00-manifests/cm-file-demo.yaml
   kubectl apply -f 00-manifests/cm-file-demo.yaml
   kubectl wait --for=condition=Ready pod/cm-file-demo --timeout=60s
   ```
   Expected: Pod Running.

2. "Each key is now a file."
   ```bash
   kubectl exec cm-file-demo -- ls /etc/appconfig
   ```
   Expected: `APP_COLOR  APP_MODE  app.properties`.

3. "Read the config file key."
   ```bash
   kubectl exec cm-file-demo -- cat /etc/appconfig/app.properties
   ```
   Expected: the three-line properties content.

4. "Clean up the Pod (keep the ConfigMap)."
   ```bash
   kubectl delete pod cm-file-demo
   ```

**✅ Conclusions:**

- Mounting a ConfigMap turns each key into a file.
- Great for whole config files the app reads from disk.
- Next: Secrets — the same ideas, for sensitive data.

## ConfigMap - Secrets | Types & the base64 Truth

**Learning objective:** create a Secret and understand that base64 is not encryption.

"Secrets are where passwords and tokens live. But here's the dangerous misconception: a Secret is NOT encrypted by default. Let me prove it by decoding one in two seconds."

0. "Imperative first — create the Secret from literals."
   ```bash
   kubectl create secret generic app-secret --from-literal=DB_USER=shop_app --from-literal=DB_PASSWORD='s3cr3t-p@ss'
   kubectl get secret app-secret
   ```
   Expected: an Opaque Secret, two keys. Now the committable version using
   `stringData` (readable in git diffs).
   ```bash
   kubectl delete secret app-secret
   ```

1. "Create a Secret with stringData (plain text in, base64 stored)."
   ```bash
   kubectl apply -f 00-manifests/app-secret.yaml
   kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo
   ```
   Expected: a base64 string (not the plaintext).

2. "Now decode it — this is the whole 'security' of base64."
   ```bash
   kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
   ```
   Expected: `s3cr3t-p@ss` — fully readable.

3. "See the type and keys."
   ```bash
   kubectl get secret app-secret -o jsonpath='{.type}'; echo
   kubectl describe secret app-secret
   ```
   Expected: type `Opaque`; keys listed with byte counts (values hidden in describe).

**✅ Conclusions:**

- base64 ≠ encryption; Secrets are decodable by anyone with read access.
- Protect with RBAC + etcd encryption + external managers.
- Next: consume Secrets in Pods without leaking them.