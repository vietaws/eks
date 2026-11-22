# 30 — Run many pods per EC2 node without using VPC subnet IPs

## 🎯 Scenario
The default AWS VPC CNI gives every pod an IP from a VPC subnet. Two problems follow: subnets run out of IPs, and the instance's ENI/IP limit caps pods per node (`24-max-pod`: t3.medium = 17 pods). This demo set shows two ways out and compares them with the default.

| Sub-demo | Approach | Pod IPs come from | Max pods on t3.medium |
|---|---|---|---|
| `24-max-pod` (baseline) | default VPC CNI | main subnets | 17 |
| [`01-cilium-overlay`](01-cilium-overlay/README.md) | Cilium overlay (VXLAN) replaces the VPC CNI | private pool `192.168.0.0/16`, **no VPC IPs** | 110 (kubelet `maxPods`) |
| [`02-secondary-cidr`](02-secondary-cidr/README.md) | VPC CNI custom networking, then + prefix delegation | secondary VPC CIDR `100.64.0.0/16` | 12, then 110 with prefix delegation |

Both demos use a **new cluster**, **public subnets only**, **public node IPs** and **no NAT gateway**, and finish with an ALB in front of ~100 pods of `vietaws/eks:v1`.

## 📊 Comparison

Sources: [Cilium on EKS](https://docs.cilium.io/en/stable/installation/k8s-install-helm/), [Calico on EKS](https://docs.tigera.io/calico/latest/getting-started/kubernetes/managed-public-cloud/eks), [EKS alternate CNIs](https://docs.aws.amazon.com/eks/latest/userguide/alternate-cni-plugins.html), [EKS custom networking](https://docs.aws.amazon.com/eks/latest/userguide/cni-custom-network.html), [IP optimization best practices](https://docs.aws.amazon.com/eks/latest/best-practices/ip-opt.html).
Performance rows are qualitative from how each datapath works. They are **not benchmarks**.

| | Cilium overlay | Calico (own networking) | VPC CNI + secondary CIDR |
|---|---|---|---|
| Uses VPC subnet IPs for pods | No | No | Yes, from the secondary CIDR (main subnets spared) |
| Software cost | Free (OSS) | Free (OSS) | Free (EKS add-on) |
| Pods per node | kubelet `maxPods` (110 default) | same (the Calico guide uses 100) | 12 on t3.medium; 110 only with prefix delegation |
| Datapath | VXLAN encapsulation, eBPF available | VXLAN or other modes, iptables or eBPF | native VPC routing, no encapsulation |
| Pods routable from the VPC | No (SNAT to node IP) | No | Yes |
| ALB target type | `instance` only | `instance` only | `ip` or `instance` |
| API-server-to-pod webhooks | need `hostNetwork` | need `hostNetwork` | work normally |
| Who supports it | partner / commercial / you | partner / commercial / you | AWS |
| Extra ops work | CNI install and upgrades, tunnel MTU | same | ENIConfig per AZ, node replacement per change |
| EKS Auto Mode | not supported | not supported | n/a (Auto Mode manages networking) |

Cost note: none of the three charges per pod. Real cost differences are indirect: denser nodes need fewer EC2 instances, and an unsupported CNI costs engineering time or a support contract. Check current prices on the [EKS](https://aws.amazon.com/eks/pricing/), [EC2](https://aws.amazon.com/ec2/pricing/on-demand/) and [ELB](https://aws.amazon.com/elasticloadbalancing/pricing/) pages.

### Which one to choose
| Scenario | Pick |
|---|---|
| Subnets are nearly full, you want the least change and AWS support | Secondary CIDR (add prefix delegation if you also need density) |
| Very high pod density per node, pods never need to be reached from the VPC | Cilium overlay |
| Other VPC workloads must call pods directly, or ALB/NLB `ip` targets are required | Secondary CIDR |
| You already run Calico for network policy and accept the overlay limits | Calico networking |
| New cluster and IPv6 is possible | IPv6 cluster (AWS's first recommendation), not covered here |
| Compliance requires AWS-only supported components | Secondary CIDR |

## ✅ Prerequisites
- AWS CLI profile `eks`, region `ap-southeast-1`, `terraform` ≥ 1.5, `kubectl`, `helm`, `jq`.
- Read [`24-max-pod`](../24-max-pod/README.MD) for the ENI formula (this demo does not modify it).

## 🚀 Steps
Run the demos **one at a time** and destroy each cluster before starting the next.
1. [`01-cilium-overlay`](01-cilium-overlay/README.md)
2. [`02-secondary-cidr`](02-secondary-cidr/README.md)

Shared file: `iam_policy.json` is the upstream AWS Load Balancer Controller policy, used by both Terraform stacks.

## 🔍 Validation
Each sub-demo compares `AvailableIpAddressCount` of the subnets before and after scaling to 100 pods, lists pods per node, and tests pod-to-pod, pod-to-internet and ALB access.

## 🧹 Cleanup
Follow the Cleanup section of each sub-demo. Delete the ALB before `terraform destroy`.

## 📝 Notes & cost
- Not applied or tested against a live AWS account when written: both Terraform stacks pass `terraform validate`, and the Helm values and manifests render and pass `kubectl --dry-run`. Report any behavior that differs from the README.
- Demo-grade security: public subnets, public node IPs, open egress. Do not use this layout in production.
