# PART 2 — Amazon EKS Hands-on Demos

A collection of focused, folder-based EKS demos covering networking, storage, autoscaling, serverless compute (Fargate), Infrastructure-as-Code, and GitOps.

Each demo is self-contained and documented with the **same README structure** so you always know what you are about to run, what it costs, and how to clean it up.

---

## 📁 Demo Index

| #  | Folder                        | Topic                                   | Creates billable resources? |
|----|-------------------------------|-----------------------------------------|-----------------------------|
| 01 | `01-prep`                     | Install AWS CLI, eksctl, kubectl        | No                          |
| 02 | `02-create-eks-cluster`       | Create cluster + node group (eksctl)    | **Yes** (EKS + EC2)         |
| 03 | `03-clb`                      | Classic Load Balancer (legacy)          | **Yes** (CLB)               |
| 04 | `04-nlb`                      | Network Load Balancer                   | **Yes** (NLB)               |
| 05 | `05-nlb-internal`             | Internal NLB                            | **Yes** (NLB)               |
| 06 | `06-alb`                      | Install AWS Load Balancer Controller    | **Yes** (ALB)               |
| 07 | `07-alb-path-routing`         | ALB path-based routing                  | **Yes** (ALB)               |
| 08 | `08-alb-acm`                  | ALB + HTTPS with ACM                    | **Yes** (ALB)               |
| 09 | `09-alb-https-redirect`       | ALB HTTP→HTTPS redirect                 | **Yes** (ALB)               |
| 10 | `10-route53`                  | ExternalDNS + Route 53                  | **Yes** (ALB + R53)         |
| 11 | `11-auto-asign-custom-domain` | Auto-assign custom domain via ExternalDNS | **Yes** (ALB + R53)       |
| 12 | `12-host-routing`             | ALB host-based routing                  | **Yes** (ALB)               |
| 13 | `13-ingress-group`            | IngressGroup (share one ALB)            | **Yes** (ALB)               |
| 14 | `14-single-alb-multiple-ns`   | One ALB across namespaces               | **Yes** (ALB)               |
| 15 | `15-alb-target-ip`            | ALB target-type `ip`                    | **Yes** (ALB)               |
| 16 | `16-internal-alb`             | Internal ALB                            | **Yes** (ALB)               |
| 17 | `17-fargate`                  | Fargate profile basics                  | **Yes** (Fargate)           |
| 18 | `18-fargate-multiple-profiles`| Multiple Fargate profiles               | **Yes** (Fargate)           |
| 19 | `19-hpa`                      | Horizontal Pod Autoscaler               | No (uses existing nodes)    |
| 20 | `20-vpa`                      | Vertical Pod Autoscaler                 | No                          |
| 21 | `21-cluster-autoscaler`       | Cluster Autoscaler (classic)            | **Yes** (EC2 scale-out)     |
| 22 | `22-karpenter`                | Karpenter node autoscaling              | **Yes** (EC2 scale-out)     |
| 23 | `23-ebs`                      | EBS CSI driver + dynamic provisioning   | **Yes** (EBS)               |
| 24 | `24-max-pod`                  | Max pods per node (ENI/IP math)         | No                          |
| 25 | `25-multi-az-pods`            | Multi-AZ PV scheduling                  | **Yes** (EBS)               |
| 26 | `26-efs`                      | EFS CSI driver (static + dynamic)       | **Yes** (EFS)               |
| 27 | `27-instance-store`           | NVMe instance-store PVs (+ RAID-0)      | **Yes** ($$ large EC2)      |
| 28 | `28-terraform`                | Provision EKS with Terraform            | **Yes** (EKS + EC2 + NAT)   |
| 29 | `29-argocd`                   | GitOps with Argo CD                     | **Yes** (runs on cluster)   |

---

## 🧱 Standard README structure

Every demo README follows the same sections:

1. **🎯 Scenario** — what the demo teaches and why it matters.
2. **🗺️ Architecture** — what gets created (text diagram / bullet list).
3. **✅ Prerequisites** — cluster, controllers, tools required.
4. **🚀 Steps** — copy-paste commands, in order.
5. **🔍 Validation** — how to confirm it works.
6. **🧹 Cleanup** — remove everything billable.
7. **📝 Notes & cost** — gotchas, modern alternatives, cost tips.

---

## ⚙️ Conventions used across all demos

| Setting        | Value                         |
|----------------|-------------------------------|
| Region         | `ap-southeast-1` (Singapore)  |
| AWS CLI profile| `eks`                         |
| Cluster name   | `vietvn` (replace as needed) |
| Demo app image | `vietaws/eks:home`, `vietaws/eks:v1` (Docker Hub, public) |

> Replace the region, profile, cluster name, account ID, domain, and certificate ARN placeholders with **your own** values. Never commit real account IDs, certificate ARNs, or secrets — see the security note below.

---

## 🔐 Security note (read before running)

These demos are optimized for **learning**, not production. In particular:

- IAM steps may use broad permissions (e.g. `AdministratorAccess`, `Resource: "*"`). In production, follow least privilege.
- Do **not** paste real AWS Account IDs, ACM certificate ARNs, OIDC IDs, or admin passwords into manifests or READMEs. Use placeholders:
  `ACCOUNT_ID`, `CERT_ARN`, `OIDC_ID`, `<your-domain>`.
- Prefer **EKS Pod Identity** over IRSA for new clusters (simpler, no OIDC trust policy juggling). IRSA is shown here because many tutorials still use it.

---

## 💰 Cost-saving defaults for a demo cluster

- Use **Graviton (ARM64)** instance types (`t4g`, `m7g`, `c7g`) — ~20% cheaper than equivalent x86 for the same demo.
- Use **Spot** capacity for throwaway worker nodes.
- Keep **one** NAT Gateway (or none, with public-subnet nodes) while learning.
- Set managed node group `minSize: 0` where the demo allows scale-to-zero.
- **Always run the Cleanup section** — Load Balancers, NAT, EFS, and large EC2 instances bill by the hour even when idle.
