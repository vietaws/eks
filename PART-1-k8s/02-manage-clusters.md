# Creating K8s Cluster

## 1. From scratch — simplest possible cluster (single node)
```bash
# What clusters exist right now?
kind get clusters

# Create a default single-node cluster (no config)
kind create cluster --name vietvn 
kubectl --context kind-vietvn get nodes          # ONE node (control-plane + worker)
kubectl --context kind-vietvn get nodes -o wide

# It can't demonstrate cross-node scheduling — tear it down
kind delete cluster --name vietvn
# NOTE: deleting the active cluster leaves kubectl's context dangling.
# kind sets the context when you create the course cluster below; if needed:
#   kubectl config use-context kind-k8s-course
```
Expected: `get clusters` lists existing clusters; one node `scratch-control-plane`; deletes cleanly.

## 2. Declarative — multi-node from a config file
> kind has NO flag to add worker nodes. Multiple nodes REQUIRE a config file —
> so "multi-node" and "declarative" are the same step.
```bash
# Review the cluster definition (1 control-plane + 2 workers + labels + ingress ports)
cat 01-prep/kind-config.yaml

# Create from config (or use ./cluster-up.sh which also waits for Ready)
kind create cluster --name vietvn-k8s --config 01-prep/kind-config.yaml

# Verify
kubectl get nodes -o wide
kubectl get nodes -L viet.vn/node-pool,ingress-ready
kubectl config current-context          # kind-k8s-course
kind get clusters                       # list all kind clusters
```
Expected: 3 Ready nodes (control-plane + worker + worker2); labels present.

## Common flags: kind
```
kind create cluster                     create a default single-node cluster
  --name NAME                           name the cluster (context = kind-NAME)
  --config FILE                         build from a cluster config (multi-node, labels, ports)
  --image kindest/node:vX.Y.Z           pin the Kubernetes version
  --wait 60s                            block until the control plane is ready
kind get clusters                       list clusters
kind delete cluster --name NAME         delete a cluster
kind get kubeconfig --name NAME         print the kubeconfig
kind load docker-image IMG --name NAME  load a local image into the cluster
```
