# 28 — Provision EKS with Terraform

## 🎯 Scenario
Build an EKS cluster from scratch with raw Terraform resources (VPC, subnets, IGW, NAT, route tables, EKS control plane, managed node group, add-ons) so you
understand every piece — no modules hiding the details.

## 🗺️ Architecture
```
VPC
 ├─ public  subnets (1a, 1b)  ── IGW
 ├─ private subnets (1a, 1b)  ── 1x NAT Gateway (cost-optimized)
 ├─ EKS control plane (all 4 subnets)
 └─ managed node group (public subnet) + vpc-cni add-on
```

## ✅ Prerequisites
- Terraform ≥ 1.x, AWS CLI profile `eks`.
- Files live in `00-tf-demo/`.

## 🚀 Steps
```bash
cd 00-tf-demo
terraform init
terraform fmt
terraform plan
terraform apply

# Connect
aws eks update-kubeconfig --alias tf --name eks-tf --region ap-southeast-1 --profile eks
kubectl get nodes
```

## 🔍 Validation
```bash
terraform state list
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

## 🧹 Cleanup
```bash
terraform apply -destroy       # or: terraform destroy
```
> The single NAT Gateway and the EKS control plane bill per hour — destroy when done.

## 📝 Notes & cost
Issues to be aware of / improve in this demo (kept simple on purpose):

- **Pin the Kubernetes version** (`6-eks.tf` sets `version = "1.37"`). Bump to a currently-supported EKS version and treat it as a variable.
- **Pin add-on versions.** `7-addon.tf` installs `vpc-cni` with no `addon_version`/`resolve_conflicts` — pin it and add `coredns`, `kube-proxy`, and `aws-ebs-csi-driver` for a complete cluster.
- **Node placement.** The node group runs in a **single public subnet** (`8-node-group.tf`). For production, use the **private** subnets across both AZs. The single-subnet choice avoids cross-AZ data charges while testing but sacrifices AZ resilience.
- **Auth.** No IRSA / EKS Pod Identity is configured. Add the EKS Pod Identity agent + associations for add-ons that need AWS permissions.
- **AMI.** Managed node groups now default to **AL2023** (AL2 is end-of-support); don't pin an AL2 AMI type.

**Cost-savers already present:** NAT #2 is commented out in `4-nat.tf` (single NAT), and the node group `min_size = 0`. Consider Graviton (`t4g`/`m7g`) +
`capacity_type = "SPOT"` for a throwaway demo.
