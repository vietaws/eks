Turn the plain manifests into one Helm chart.

Repo stage: tag `v3-helm-chart` in https://github.com/vietaws/argocd-demo.git

# 1️⃣ Does the cluster need anything for Helm?

No. Helm runs outside the cluster (your laptop, CI, or the Argo CD `repo-server`). It renders templates into plain YAML, and the Kubernetes API server only receives that YAML.

# 2️⃣ Chart structure

```
charts/myapp/
├── Chart.yaml            # name and version
├── values.yaml           # default values
└── templates/
    ├── deployment.yaml   # same as app/deployment.yaml, with {{ .Values.* }}
    ├── service.yaml
    └── ingress.yaml      # optional ALB, rendered only when ingress.enabled is true
```

Template excerpt:

```yaml
replicas: {{ .Values.replicas }}
...
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

The resource names come from `{{ .Release.Name }}`, so the same chart can deploy `myapp`, `orders`, and others.

# 3️⃣ Test locally (no cluster needed)

```
git clone https://github.com/vietaws/argocd-demo.git && cd argocd-demo

helm lint charts/myapp
helm template myapp charts/myapp
```

✅ The rendered Deployment and Service are the same as `app/deployment.yaml` and `app/service.yaml`.

Compare with the original:

```
diff <(helm template myapp charts/myapp) <(cat app/deployment.yaml app/service.yaml)
# Only whitespace, ordering, and the quotes around the image differ
```

Each environment gets its own ALB. Check that the Ingress renders for dev and prod but not for `orders`:

```
helm template myapp charts/myapp -f envs/dev/values.yaml  | grep -A4 "kind: Ingress"   # vietvn-argocd-dev-alb
helm template myapp charts/myapp -f envs/prod/values.yaml | grep -A4 "kind: Ingress"   # vietvn-argocd-prod-alb
helm template orders charts/myapp -f envs/dev/orders.yaml | grep -c "kind: Ingress"    # 0
```

💡 Nothing is deployed in this step. Argo CD still points at `app/`.
