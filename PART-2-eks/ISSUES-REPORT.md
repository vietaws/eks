# EKS Demo Repo — Audit & Issues Report

_Audited: 2026-10-23. Scope: all 29 demo folders (`01-prep` … `29-argocd`)._
_Version facts verified against live AWS/Kubernetes docs: EKS supports Kubernetes
up to **1.37**; Amazon Linux 2 (AL2) EKS AMIs reached **end-of-support 2025-11-26**
(use **AL2023**); **Karpenter v1** is GA (stable API `karpenter.sh/v1`)._

---

## 🔴 CRITICAL (security / data exposure) — all fixed in this pass

| # | Location | Issue | Fix applied |
|---|----------|-------|-------------|
| C1 | `08-alb-acm/manifests/05-alb.yaml`, `09-alb-https-redirect/manifests/05-alb.yaml` | Hardcoded **real ACM certificate ARN** containing real account `825770460273`. | Replaced with `arn:aws:acm:...:ACCOUNT_ID:certificate/CERT_ID` placeholder + TODO. |
| C2 | `23-ebs/01-basics/trust-policy.json`, `26-efs/01-config/trust-policy.json`, `26-efs/01-config/public-ecr-driver.yaml` | Real **account ID + OIDC provider ID** baked into IAM trust policies / role ARN. | Replaced with `ACCOUNT_ID` / `OIDC_ID` placeholders. JSON re-validated. |
| C3 | `29-argocd/02-install.md` | **Real Argo CD admin password** exposed in plaintext **and** base64 in the committed doc. | Removed the value; replaced with a `jsonpath | base64 -d` command and a "rotate + delete bootstrap secret" hardening step. |
| C4 | READMEs: `01-prep`, `10-route53`, `23-ebs`, `26-efs`, `22-karpenter/01-configure` | Real account IDs (`825770460273`, `957323120273`) sprinkled through example output. | Sanitized to `ACCOUNT_ID` throughout. |
| C5 | `01-prep/00-install.md` | Example `aws configure` showed inline access-key/secret strings with no warning. | Replaced with `<YOUR_ACCESS_KEY_ID>` placeholders + a "never paste real keys; prefer SSO/roles" warning. |

> ✅ Post-fix verification: `grep -rn` for the account IDs, the cert ARN, and the
> base64 password returns **CLEAN** across the repo.

---

## 🟠 MEDIUM (technical currency / correctness)

| # | Location | Issue | Recommendation / status |
|---|----------|-------|--------------------------|
| M1 | `22-karpenter/*` | Used **deprecated Karpenter `v1beta1` API**, `v0.37.0`, `amiFamily: AL2`, `consolidationPolicy: WhenUnderutilized`. | Updated `nodeclass.yaml`, `02-implement`, `03-consolidation`, and `04-install.md` to **`karpenter.sh/v1`**, `amiFamily: AL2023`, `amiSelectorTerms: [{alias: al2023@latest}]`, `nodeClassRef` with `group/kind/name`, and `consolidationPolicy: WhenEmptyOrUnderutilized` + explicit `consolidateAfter`. |
| M2 | Everywhere nodes are created (`02`, Karpenter, Terraform, instance-store) | **`AL2` / `AmazonLinux2` AMI family** — end-of-support 2025-11-26. | Switch to **AL2023**. Updated in Karpenter + noted in Terraform README. |
| M3 | `04-nlb`, `05-nlb-internal` | Legacy **in-tree** annotation `service.beta.kubernetes.io/aws-load-balancer-type: nlb`. | Documented modern **AWS Load Balancer Controller** path: `loadBalancerClass: service.k8s.aws/nlb` + `aws-load-balancer-scheme`/`nlb-target-type: ip`. |
| M4 | `03-clb` | **Classic Load Balancer** is legacy. | Kept for teaching but clearly marked deprecated and pointed to NLB/ALB. |
| M5 | `28-terraform/00-tf-demo` | `version = "1.29"` hardcoded; `vpc-cni` add-on **not version-pinned**; only `vpc-cni` (missing coredns/kube-proxy/ebs-csi); node group in a **single public subnet**; no IRSA/Pod Identity. | Documented all four in the README's Notes with concrete fixes (pin version as a variable, pin + add add-ons, use private subnets across AZs, add Pod Identity). Code left runnable; improvements called out. |
| M6 | `06`–`16` (ALB/ingress), `10-route53` | Auth via **IRSA** everywhere. | EKS **Pod Identity** is the modern recommendation (simpler, no OIDC trust-policy juggling). Noted in each relevant README; Karpenter install already uses Pod Identity. |
| M7 | `21-cluster-autoscaler` | Still valid, but CA is the older approach. | Kept; added prominent pointer to **Karpenter (`22`)** as the modern default, and the hard rule that the CA image must match the cluster's K8s minor version. |
| M8 | `19-hpa` | `metrics-server v0.7.1` pinned; load-gen used a third-party image (`devth/alpine-bench`). | Switched install to `/releases/latest/`; load generator example uses stock `busybox`. |
| M9 | `10-route53/manifests/01-external-dns.yaml` | `external-dns:v0.23.0` pinned + stale role ARN. | README now instructs to pin the **latest** release and use `ACCOUNT_ID` placeholder. (Manifest tag left; flagged to update.) |
| M10 | `02-create-eks-cluster/03-eksctl-command.md` vs `01-create-eks-cluster.md` | Docs reference K8s **1.37** but `eksctl create cluster` has **no `--version`**, so you silently get the eksctl default. | Recommend always pinning `--version`. (Doc-level; flagged.) |

---

## 🟡 LOW (cost, consistency, polish)

| # | Location | Issue | Recommendation / status |
|---|----------|-------|--------------------------|
| L1 | `27-instance-store/02-multiple-pv/ng.yaml`, `03-implement-raid-0/ng.yaml` | **`i3.8xlarge`** (~$2.5/hr) used purely for a storage demo. | Dropped to **`i3.4xlarge`** (still ≥2 NVMe disks for the "multiple PV"/RAID-0 scenarios) + big cost warnings + teardown reminders in the READMEs. |
| L2 | Default node type `t3.medium` on-demand (`02`, Karpenter bootstrap, Terraform) | x86 on-demand is the priciest demo option. | Recommend **Graviton** (`t4g`/`m7g`) + **Spot**; Karpenter NodePool now allows `arm64` + `spot`. Root README documents cost defaults. |
| L3 | Many LB demos (`03`–`16`) | **Cleanup sections were missing/inconsistent**; ALBs/NLBs bill hourly. | Every rewritten README now has a **🧹 Cleanup** section + a per-demo cost note. |
| L4 | ~14 READMEs were **empty (0 bytes)** or 1–2 lines (`07,08,09,11,12,15,16` empty; `03,04,05,13,14,23,26` near-empty) | No scenario/steps/validation. | **All rewritten** to the standard 7-section structure. 0-byte READMEs now = **0**. |
| L5 | Inconsistent file naming (`readme.md`, `README.md`, `README.MD`) and cluster names (`vietvn`, `vietaws6`, `karpenter6`) across demos | Confusing to follow. | Root README defines a single convention (cluster `eksdemo`, region `ap-southeast-1`, profile `eks`); rewritten docs use it. (Existing lowercase/uppercase filenames left as-is to avoid churn on a case-insensitive FS.) |
| L6 | `01-prep/00-install.md` | eksctl install snippet set `PLATFORM=windows_$ARCH` in a **macOS** guide. | Fixed to `Darwin_arm64`. |
| L7 | `23-ebs/01-basics` | Inline EBS IAM policy uses `Resource: "*"`. | README now steers to the AWS-managed **`AmazonEBSCSIDriverPolicy`** (already shown as the recommended approach). |

---

## ➕ Suggested NEW demos (optional, high teaching value)

1. **EKS Pod Identity** standalone demo (vs IRSA) — it's referenced everywhere as
   the modern default but never shown end-to-end outside Karpenter.
2. **gp3 vs gp2 + VPC CNI prefix delegation** cost/scale demo (ties into `24-max-pod`).
3. **EKS Auto Mode** — AWS now offers fully-managed compute/autoscaling; worth a
   short demo alongside Karpenter.
4. **Gateway API** (via AWS Gateway API Controller) as the successor pattern to
   Ingress for `06`–`16`.

## ➖ Candidates to retire / de-emphasize

- `03-clb` — keep only as a "this is legacy, don't use" footnote.
- `21-cluster-autoscaler` — demote to "legacy/alternative"; Karpenter is the
  default recommendation.

---

## ✅ What changed in this pass (summary)
- Rewrote the **root README** (index, standard structure, conventions, security &
  cost notes) and **every demo README** to the 7-section template:
  Scenario / Architecture / Prerequisites / Steps / Validation / Cleanup / Notes.
- **Removed all exposed secrets**: real ACM cert ARN, account IDs, OIDC IDs, and
  the Argo CD admin password → placeholders. Verified clean via grep.
- **Modernized Karpenter** manifests/docs to the GA v1 API + AL2023 + Pod Identity.
- **Cost fixes**: `i3.8xlarge → i3.4xlarge` in instance-store, Graviton+Spot
  guidance, consistent cleanup/cost sections.
- **Correctness fixes**: macOS eksctl platform, IAM policy guidance, metrics-server
  install.
