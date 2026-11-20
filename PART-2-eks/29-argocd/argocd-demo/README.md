# argocd-demo - vietaws

Sample manifest repo for the Argo CD on EKS demo. Argo CD watches this repo and deploys the manifests to the cluster.

The repo grows in stages. Each stage has a git tag, so you can follow the demo step by step.

## Structure

```
argocd-demo/
├── app/                     # stage 1: plain manifests, dev (myapp, 2 replicas, image vietaws/eks:v1, port 8080)
│   ├── deployment.yaml
│   └── service.yaml
├── app-prod/                # stage 2: plain copy of app/ with 3 replicas
├── charts/myapp/            # stage 3: one Helm chart for every service
│   ├── Chart.yaml
│   ├── values.yaml          # defaults
│   └── templates/
└── envs/                    # stage 4+: values per environment or service
    ├── dev/
    │   ├── values.yaml          # myapp dev: 1 replica, APP_ENV=dev, blue background, LOG_LEVEL=debug
    │   └── orders.yaml          # stage 5: new service, values only
    └── prod/
        └── values.yaml          # myapp prod: 3 replicas, APP_ENV=prod, green background, LOG_LEVEL=info
```

| Tag | Stage | Argo CD Application path |
|---|---|---|
| `v1-plain` | Plain manifests, one environment | `app` |
| `v2-multi-env-plain` | Plain manifests copied for prod | `app`, `app-prod` |
| `v3-helm-chart` | Helm chart, not deployed yet | none (test with `helm template`) |
| `v4-helm-envs` | One chart, values per environment | `charts/myapp` + `envs/<env>/values.yaml` |
| `v5-new-service` | New `orders` service from a values file | `charts/myapp` + `envs/dev/orders.yaml` |
| `v8-env-values` | Per-env app settings (`appEnv`, `backgroundColor`, `logLevel`, `appVersion`) and `/healthz` probes | `charts/myapp` + `envs/<env>/values.yaml` |

`app/` and `app-prod/` stay on `main` as the plain-manifest baseline. After stage 4 nothing syncs them.

The Application and ApplicationSet manifests are in the docs folder (`PART-2-eks/29-argocd/`), not in this repo.

## Usage

Point an Argo CD Application at this repo:

- Repo URL: `https://github.com/vietaws/argocd-demo.git`
- Revision: `HEAD` (default branch `main`)
- Path: `app` (plain) or `charts/myapp` (Helm)
- Destination namespace: `myapp`

Argo CD reads from GitHub, not from a local copy, so push changes before expecting a sync. Push tags with `git push origin main --tags`.

## Try it

Plain stage:

1. Change `replicas` in `app/deployment.yaml`, then commit and push. Argo CD syncs the change.
2. Change the image tag (for example `v1` to `v2`) and push to roll out a new version.
3. Run `kubectl scale deploy myapp -n myapp --replicas=5`. With `selfHeal` enabled, Argo CD reverts it to the Git value.
4. Run `kubectl delete deploy myapp -n myapp`. Argo CD recreates it.

Helm stage:

1. Render locally: `helm template myapp charts/myapp -f envs/dev/values.yaml`.
2. Change `replicas` in `envs/prod/values.yaml`. Only prod changes.
3. Change a template in `charts/myapp/templates/`. Every environment and service changes.
4. Copy `envs/dev/orders.yaml` to add another service.
5. Change `backgroundColor` in `envs/prod/values.yaml` and push. After the sync the prod page changes color (dev is blue, prod is green).

Chart values for the `vietaws/eks` image (empty means the variable is not set):

| Value | Env var | Notes |
|---|---|---|
| `appEnv` | `APP_ENV` | Shown on the page, for example `dev` or `prod` |
| `backgroundColor` | `BACKGROUND_COLOR` | Page background |
| `logLevel` | `LOG_LEVEL` | `error`, `warn`, `info`, `debug` |
| `appVersion` | `APP_VERSION` | `auto` uses `image.tag` without the leading `v` |
| `probes.enabled` | none | Readiness and liveness probes on `/healthz` |
| `env` | any | Extra raw variables, used by non-app images such as `orders` (nginx) |
