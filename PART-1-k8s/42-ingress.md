# Install ingress-nginx on kind

**Learning objective:** install an ingress controller so Ingress resources work.

"An Ingress resource is just a rulebook — it does nothing without a controller to enforce it. Let's install ingress-nginx, using kind's purpose-built manifest."

## Install

1. "Apply kind's ingress-nginx manifest."
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
   ```
   Expected: resources created in the `ingress-nginx` namespace.

2. "Wait for the controller Pod to be ready."
   ```bash
   kubectl wait --namespace ingress-nginx \
     --for=condition=Ready pod \
     --selector=app.kubernetes.io/component=controller --timeout=150s
   ```
   Expected: the controller Pod becomes Ready.

3. "Confirm the IngressClass exists — Ingress resources reference it."
   ```bash
   kubectl get ingressclass
   kubectl get pods -n ingress-nginx
   ```
   Expected: an IngressClass named `nginx`; controller Running.

**✅ Conclusions:**

- Ingress needs a controller; we installed ingress-nginx (kind variant).
- It binds host ports 80/443 (from our kind config) and provides the `nginx` class.
- Next: write Ingress rules to route traffic.

## Ingress Resources & Routing

**Learning objective:** route external HTTP to multiple Services by path.

"One entry point, many backends. `/` goes to the web app, `/api` to the API — all through one Ingress, one IP. Let's wire it up and curl both paths."

1. "Deploy two backends + Services + the Ingress."
   ```bash
   cat 00-manifests/ingress-demo.yaml
   kubectl apply -f 00-manifests/ingress-demo.yaml
   kubectl rollout status deploy/web
   kubectl rollout status deploy/api
   kubectl get ingress shop
   ```
   Expected: an Ingress `shop` with an address.

2. "Hit `/` — routed to the web (nginx) backend."
   ```bash
   kubectl run c --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- \
     curl -s http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/ | grep -o '<title>.*</title>'
   ```
   Expected: `<title>Welcome to nginx!</title>`.

3. "Hit `/api` — routed to the api (http-echo) backend."
   ```bash
   kubectl run c --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- \
     curl -s http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/api
   ```
   Expected: `hello from API`.
   (From your host machine with kind's port map: `curl localhost/` and `curl localhost/api`.)

4. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/ingress-demo.yaml
   ```

**✅ Conclusions:**

- One Ingress routes many paths/hosts to different Services.
- The controller enforces the rules; `rewrite-target` reshapes the path.
- On kind, reach it at `localhost` (host ports) or the controller Service.
- Next: TLS termination at the Ingress.

## Ingress TLS

**Learning objective:** understand how an Ingress terminates HTTPS using a TLS Secret.

"Production traffic is HTTPS. The good news: you usually terminate TLS at the Ingress, so your apps keep speaking plain HTTP. Let's see how the pieces fit."

1. "Create a self-signed cert and a TLS Secret (demo only)."
   ```bash
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout tls.key -out tls.crt -subj "/CN=demo.local" >/dev/null 2>&1
   kubectl create secret tls demo-tls --cert=tls.crt --key=tls.key
   kubectl get secret demo-tls
   ```
   Expected: a Secret of type `kubernetes.io/tls`.

2. "Reference it in an Ingress `spec.tls` (shown in 00-manifests/ingress-tls.yaml)."
   ```bash
   grep -A4 'tls:' 00-manifests/ingress-tls.yaml
   ```
   Expected: a `tls` block binding `demo-tls` to host `demo.local`.

3. "In production, cert-manager issues/renews these automatically — you annotate the Ingress and it handles the rest."
   ```bash
   kubectl delete secret demo-tls; rm -f tls.key tls.crt
   ```

**✅ Conclusions:**

- TLS Secret (cert+key) + `spec.tls` in the Ingress = HTTPS termination.
- The controller decrypts; your Service still gets plain HTTP.
- Use cert-manager to automate certs in real clusters. Next: tie it all together.

## Putting Together

**Learning objective:** combine a namespace, RBAC, and an Ingress for one app.

"Let's assemble the section: deploy an app into its own namespace, scope a ServiceAccount's permissions, and expose it through an Ingress — the shape of a real deployment."

1. "Create a namespace and deploy the two-backend app there."
   ```bash
   kubectl create namespace course-shop
   kubectl -n course-shop apply -f 00-manifests/ingress-demo.yaml
   kubectl -n course-shop rollout status deploy/web
   ```
   Expected: app running in `course-shop`.

2. "Scope a read-only ServiceAccount in that namespace."
   ```bash
   kubectl -n course-shop create serviceaccount viewer
   kubectl -n course-shop create role viewer --verb=get,list --resource=pods,services
   kubectl -n course-shop create rolebinding viewer --role=viewer --serviceaccount=course-shop:viewer
   kubectl auth can-i list services -n course-shop --as=system:serviceaccount:course-shop:viewer   # yes
   kubectl auth can-i delete pods -n course-shop --as=system:serviceaccount:course-shop:viewer     # no
   ```
   Expected: `yes` then `no`.

3. "The Ingress routes to the app's Services (as in lesson 6)."
   ```bash
   kubectl -n course-shop get ingress,svc
   ```
   Expected: the Ingress + web/api Services present.

4. "Tear it all down with the namespace."
   ```bash
   kubectl delete namespace course-shop
   ```

**✅ Conclusions:**

- Real apps = namespace + RBAC + Services + Ingress, together.
- Deleting the namespace cleans up everything in one command.
- You now have every building block for the capstone. On to it!