resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.k8s_version
  role_arn = aws_iam_role.cluster.arn

  # Do NOT auto-install vpc-cni / kube-proxy / coredns: Cilium replaces the VPC CNI.
  # kube-proxy and CoreDNS are added as EKS add-ons in phase 2 (nodes.tf).
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Explicit service CIDR: must not overlap the VPC (10.0.0.0/16) or the Cilium pod CIDR (192.168.0.0/16).
  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
  }

  vpc_config {
    subnet_ids = aws_subnet.public[*].id
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}
