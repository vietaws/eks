variable "profile" {
  type    = string
  default = null # null = default AWS credential chain
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type    = string
  default = "vietvn-overlay"
}

variable "k8s_version" {
  type    = string
  default = "1.37"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_count" {
  type    = number
  default = 2
}

# kubelet maxPods. With an overlay CNI the ENI/IP limit no longer applies,
# so the Kubernetes default of 110 becomes the cap.
variable "max_pods" {
  type    = number
  default = 110
}

# Two-phase apply (see README):
#   phase 1 (false): VPC + control plane + IAM + kube-proxy/pod-identity add-ons -> then install Cilium with Helm
#   phase 2 (true) : managed node group + CoreDNS add-on
variable "create_nodes" {
  type    = bool
  default = false
}
