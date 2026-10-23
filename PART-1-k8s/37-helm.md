# Why Helm?

**Learning objective:** explain what Helm adds over raw `kubectl apply`.

"You've got a Deployment, Service, ConfigMap, Secret — and you need slightly different versions for dev, staging, and prod. Copy-pasting YAML is a maintenance nightmare. Helm fixes it."

## Install

1. "Confirm Helm is installed."
   ```bash
   helm version
   ```
   Expected: a v3 or v4 version string.

2. "No releases yet."
   ```bash
   helm list
   ```
   Expected: empty table.

3. "The three verbs we'll live in: install, upgrade, rollback — plus list/history.
   Everything else is building charts to feed them."

**✅ Conclusions:**

- Helm = package manager; chart = templated manifests + values.
- Install → a versioned release you can upgrade/roll back.
- Next: install a real chart from a public repo.

## Install Chart

**Learning objective:** add a chart repo and install a public chart as a release.

"Need Redis, Postgres, or a demo app running in 30 seconds? Someone's already written the chart. Let's add a repo and install one."

1. "Add the podinfo repo and refresh the index."
   ```bash
   helm repo add podinfo https://vietaws.github.io/podinfo
   helm repo update
   helm search repo podinfo
   ```
   Expected: the `podinfo/podinfo` chart listed.

2. "Install it as a release named demo."
   ```bash
   helm install demo podinfo/podinfo --set replicaCount=1
   kubectl rollout status deploy/demo-podinfo
   ```
   Expected: `STATUS: deployed`; the Deployment rolls out.

3. "See what Helm created and the release metadata."
   ```bash
   helm list
   kubectl get deploy,svc -l app.kubernetes.io/name=podinfo
   helm get values demo
   ```
   Expected: one release `demo`; a Deployment + Service; your `replicaCount: 1` override.

4. "Uninstall — Helm removes everything it created."
   ```bash
   helm uninstall demo
   ```
   Expected: `release "demo" uninstalled`.

**✅ Conclusions:**

- `helm repo add` + `helm install repo/chart` = running app in seconds.
- A release bundles all the chart's objects under one name.
- `helm uninstall` cleans them all up. Next: customizing with values.

## Helm Values

**Learning objective:** customize a chart with --set and a values file.

"Same chart, different settings per environment — that's the whole point of Helm. Values are the dials. Let's turn them two ways: inline and from a file."

1. "Install podinfo and override replicaCount + a message inline."
   ```bash
   helm install demo podinfo/podinfo --set replicaCount=2 --set ui.message="hello from Helm"
   kubectl rollout status deploy/demo-podinfo
   helm get values demo
   ```
   Expected: user-supplied values show replicaCount 2 and the message.

2. "Prefer a file for real environments."
   ```bash
   cat 00-manifests/prod-values.yaml
   helm upgrade demo podinfo/podinfo -f 00-manifests/prod-values.yaml
   helm get values demo
   ```
   Expected: values now reflect the file.

3. "Clean up."
   ```bash
   helm uninstall demo
   ```

**✅ Conclusions:**

- Override with `--set` (quick) or `-f file` (per-environment).
- Precedence: defaults < -f < --set.
- `helm get values` shows the effective overrides. Next: build your own chart.

## Create Chart

**Learning objective:** scaffold a chart with `helm create`, understand its layout, and install it.

"Using charts is great; writing one is where Helm clicks. One command scaffolds a complete, working chart — let's create, tour, and install our own."

1. "Scaffold a chart (already included at 00-manifests/webapp-helm-demo — here's how it was made)."
   ```bash
   # helm create webapp-helm-demo     # (already in 00-manifests/webapp-helm-demo)
   find 00-manifests/webapp-helm-demo -maxdepth 2 -type f | sort
   ```
   Expected: Chart.yaml, values.yaml, templates/*.

2. "We pinned the image to nginx:1.27-alpine and replicaCount to 2 in values.yaml."
   ```bash
   grep -E 'replicaCount|repository|tag:' 00-manifests/webapp-helm-demo/values.yaml
   ```
   Expected: replicaCount 2, nginx, 1.27-alpine.

3. "Lint before installing — catch template errors early."
   ```bash
   helm lint 00-manifests/webapp-helm-demo
   ```
   Expected: `0 chart(s) failed`.

4. "Install our chart from the local directory."
   ```bash
   helm install web 00-manifests/webapp-helm-demo
   kubectl rollout status deploy/web-webapp
   helm list
   ```
   Expected: release `web` deployed; 2 replicas running.

5. "Leave it — we template and upgrade it in the next lessons (or clean up)."
   ```bash
   # helm uninstall web
   ```

**✅ Conclusions:**

- `helm create` scaffolds a full chart; `helm lint` validates it.
- Chart.yaml (meta) + values.yaml (defaults) + templates/ (manifests).
- Install from a local path with `helm install NAME ./chart`. Next: templating.

## Templating

**Learning objective:** read chart templates and render them with `helm template`.

"The magic of a chart is in its templates — manifests with `{{ }}` placeholders filled from values. Let's read one and render it without touching the cluster."

1. "Look at the Deployment template — note the placeholders."
   ```bash
   grep -nE 'Values|Release|include' 00-manifests/webapp-helm-demo/templates/deployment.yaml | head
   ```
   Expected: `.Values.replicaCount`, `.Values.image.*`, `include ...fullname`.

2. "Render the chart locally — no cluster changes."
   ```bash
   helm template web ./00-manifests/webapp-helm-demo | grep -E 'kind:|replicas:|image:' | head
   ```
   Expected: concrete values substituted (replicas: 2, nginx:1.27-alpine).

3. "Override a value and see the render change."
   ```bash
   helm template web ./00-manifests/webapp-helm-demo --set replicaCount=5 | grep 'replicas:'
   ```
   Expected: `replicas: 5`.

4. "Same idea against the live API with --dry-run (validates too)."
   ```bash
   helm install web ./00-manifests/webapp-helm-demo --dry-run --debug | grep -E 'replicas:' | head -1
   ```
   Expected: rendered output; nothing installed.

**✅ Conclusions:**

- Templates use `.Values`, `.Release`, `.Chart`, and `_helpers.tpl` includes.
- `helm template` / `--dry-run --debug` render locally for debugging.
- Change values → change output, no edits to templates. Next: upgrade & rollback.

## Upgrade & RollBack

**Learning objective:** manage a release's lifecycle with revisions and rollbacks.

"A chart's real payoff is the release lifecycle: every change is a numbered revision, and any bad change is one `helm rollback` away. Let's upgrade and undo."

1. "Our `web` release is at revision 1 (2 replicas)."
   ```bash
   helm list
   helm history web
   ```
   Expected: revision 1, STATUS deployed.

2. "Upgrade: bump replicas to 3 — creates revision 2."
   ```bash
   helm upgrade web ./00-manifests/webapp-helm-demo --set replicaCount=3
   kubectl rollout status deploy/web-webapp
   kubectl get deploy web-webapp -o jsonpath='{.spec.replicas}'; echo
   ```
   Expected: 3 replicas; history shows revision 2.

3. "Bad change? Roll back to revision 1 instantly."
   ```bash
   helm rollback web 1
   kubectl rollout status deploy/web-webapp
   kubectl get deploy web-webapp -o jsonpath='{.spec.replicas}'; echo
   ```
   Expected: back to 2 replicas; a new revision records the rollback.

4. "Full history, then remove the release."
   ```bash
   helm history web
   helm uninstall web
   ```
   Expected: revisions 1–3 listed; uninstall removes all objects.

**✅ Conclusions:**

- Each install/upgrade = a numbered revision; `helm history` lists them.
- `helm rollback NAME REV` restores any prior revision.
- `helm uninstall` cleans up. That's the full Helm basics loop.