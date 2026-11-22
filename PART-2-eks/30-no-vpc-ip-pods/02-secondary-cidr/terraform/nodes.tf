locals {
  # VPC CNI settings per stage. https://github.com/aws/amazon-vpc-cni-k8s#cni-configuration-variables
  vpc_cni_env = merge(
    var.stage >= 1 ? {
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone" # ENIConfig name = AZ name
    } : {},
    var.stage >= 2 ? {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    } : {}
  )

  # kubelet maxPods per stage (0 = leave the EKS default, which is the ENI formula).
  # stage 1 must be set explicitly: custom networking removes the primary ENI from pod use,
  # so the default of 17 would over-commit the node.
  max_pods = { 0 = 0, 1 = 12, 2 = 110 }[var.stage]
}

resource "aws_iam_role" "nodes" {
  name = "${var.cluster_name}-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", # optional: shell access through SSM
  ])

  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # AL2023 nodeadm config. Only set when the stage needs a non-default maxPods.
  user_data = local.max_pods == 0 ? null : base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws

    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          maxPods: ${local.max_pods}
    --BOUNDARY--
  EOT
  )
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  configuration_values        = length(local.vpc_cni_env) == 0 ? null : jsonencode({ env = local.vpc_cni_env })
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-secondary"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.public[*].id # public subnets + public IPs, no NAT gateway

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [var.instance_type]

  scaling_config {
    desired_size = var.node_count
    min_size     = 0
    max_size     = var.node_count + 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  # Nodes are replaced (rolling) whenever the launch template changes, which is how a new stage takes effect.
  update_config {
    max_unavailable = 1
  }

  # vpc-cni settings must be applied BEFORE replacement nodes start.
  depends_on = [aws_iam_role_policy_attachment.nodes, aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.this]
}
