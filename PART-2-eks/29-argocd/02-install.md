# 29.02 — Install Argo CD

> 📗 Guide: https://argo-cd.readthedocs.io/en/stable/getting_started/

## 🎯 Scenario
Install Argo CD into the cluster and log in to the UI to drive GitOps-style
deployments.

## 1️⃣ Install Argo CD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## 2️⃣ Access the UI (port-forward)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# open https://localhost:8080
```

## 3️⃣ Get the initial admin password
Username: `admin`

```bash
# Decode the auto-generated initial password straight to the terminal.
# ⚠️ Do NOT paste the decoded value into docs, screenshots, or commits.
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

## 4️⃣ Harden (recommended)
```bash
# Change the admin password, then delete the bootstrap secret
argocd login localhost:8080 --username admin --insecure
argocd account update-password
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## 🧹 Cleanup
```bash
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete namespace argocd
```

## 📝 Notes & security
- 🔐 The `argocd-initial-admin-secret` is a **real credential**. Never commit its
  plaintext or base64 value. Rotate it and delete the bootstrap secret after
  first login.
- For production, disable the local `admin` user and wire up SSO (OIDC/Dex).
- Prefer exposing the UI via an Ingress/LoadBalancer with TLS rather than
  long-lived port-forwards.
