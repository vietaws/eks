# Consuming Secrets (env + files)

**Learning objective:** inject a Secret as env vars and as mounted files.

"A Secret is useless until a Pod can read it. Two ways, same as ConfigMaps: env vars and mounted files. Let's wire both and note the security gotchas."

## Demo

1. "A Pod that takes the Secret as env AND as files."
   ```bash
   cat 00-manifests/secret-consumer.yaml
   kubectl apply -f 00-manifests/secret-consumer.yaml
   kubectl wait --for=condition=Ready pod/secret-consumer --timeout=60s
   ```
   Expected: Pod Running.

2. "Env var arrived (demo only!)."
   ```bash
   kubectl logs secret-consumer
   ```
   Expected: `user=shop_app` and a listing of `/etc/secret`.

3. "The files are there, read-only."
   ```bash
   kubectl exec secret-consumer -- sh -c 'cat /etc/secret/DB_USER; echo; cat /etc/secret/DB_PASSWORD'
   ```
   Expected: `shop_app` and `s3cr3t-p@ss`.

4. "Clean up."
   ```bash
   kubectl delete pod secret-consumer
   ```

**✅ Conclusions:**

- `secretKeyRef` for env; `secret` volume for files (tmpfs, read-only).
- Prefer files; never log secret values.
- Next: load whole ConfigMaps/Secrets at once with envFrom.

## Using envFrom

**Learning objective:** load an entire ConfigMap/Secret as env vars with envFrom.

"Referencing keys one by one gets tedious. `envFrom` loads a whole ConfigMap or Secret as env vars in one line. Let's configure a whole app from a ConfigMap + Secret together."

1. "A Deployment using envFrom (whole ConfigMap) + Secret env + a mounted file."
   ```bash
   cat 00-manifests/configured-app.yaml
   kubectl apply -f 00-manifests/configured-app.yaml
   kubectl rollout status deploy/configured-app
   ```
   Expected: 2 Pods ready.

2. "The boot log shows config from all sources."
   ```bash
   POD=$(kubectl get pod -l app=configured-app -o jsonpath='{.items[0].metadata.name}')
   kubectl logs "$POD"
   ```
   Expected: `COLOR=blue MODE=production DB_USER=shop_app` + the properties file.

3. "Note: the `app.properties` key was skipped as an env var (dot is invalid in
   a var name) but is present as a mounted file — expected behavior."
   ```bash
   kubectl exec "$POD" -- sh -c 'printenv | grep -i app_ ; echo ---; ls /etc/appconfig'
   ```
   Expected: APP_COLOR/APP_MODE in env; app.properties only as a file.

4. "Leave running — we update it next lesson."

**✅ Conclusions:**

- `envFrom` loads all keys of a ConfigMap/Secret at once.
- Mix ConfigMap + Secret + volumes freely.
- Invalid env-name keys are skipped for env but fine as files.

## Update ConfigMap

**Learning objective:** predict whether a config change reaches running Pods.

"You change a ConfigMap value in production. Does the running app see it? The answer — 'it depends how you consumed it'"

1. "Our configured-app has APP_COLOR=blue from the ConfigMap. Change it to green."
   ```bash
   kubectl patch configmap app-config --type merge -p '{"data":{"APP_COLOR":"green"}}'
   ```
   Expected: `configmap/app-config patched`.

2. "Running Pod still shows blue — env is frozen at start."
   ```bash
   POD=$(kubectl get pod -l app=configured-app -o jsonpath='{.items[0].metadata.name}')
   kubectl exec "$POD" -- printenv APP_COLOR
   ```
   Expected: `blue`.

3. "Trigger a rollout restart to pick up the new value."
   ```bash
   kubectl rollout restart deploy/configured-app
   kubectl rollout status deploy/configured-app
   NEWPOD=$(kubectl get pod -l app=configured-app -o jsonpath='{.items[0].metadata.name}')
   kubectl exec "$NEWPOD" -- printenv APP_COLOR
   ```
   Expected: `green`.

4. "Clean up the section."
   ```bash
   kubectl delete -f 00-manifests/configured-app.yaml \
     -f 00-manifests/app-config.yaml \
     -f 00-manifests/app-secret.yaml
   ```

**✅ Conclusions:**

- Env vars: frozen at start — need `rollout restart`.
- Mounted files: update in place (with delay); app must re-read.
- Tip: name ConfigMaps by content hash to force rollouts automatically.