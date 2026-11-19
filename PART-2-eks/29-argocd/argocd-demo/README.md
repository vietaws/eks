# argocd-demo - vietaws

Sample manifest repo for the Argo CD on EKS demo. Argo CD watches this repo and deploys the manifests to the cluster.

## Structure

```
argocd-demo/
└── app/
    ├── deployment.yaml   # myapp, 2 replicas, image vietaws/eks:v1, port 8080
    └── service.yaml      # myapp-service, ClusterIP, port 8080
```

## Usage

Point an Argo CD Application at this repo:

- Repo URL: `https://github.com/vietaws/argocd-demo.git`
- Revision: `HEAD` (default branch `main`)
- Path: `app`
- Destination namespace: `myapp`

Argo CD reads from GitHub, not from a local copy, so push changes before expecting a sync.

## Try it

1. Change `replicas` in `app/deployment.yaml`, then commit and push. Argo CD syncs the change.
2. Change the image tag (for example `v1` to `v2`) and push to roll out a new version.
3. Run `kubectl scale deploy myapp -n myapp --replicas=5`. With `selfHeal` enabled, Argo CD reverts it to the Git value.
4. Run `kubectl delete deploy myapp -n myapp`
