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

# NOTE: AmazonEKS_CNI_Policy is intentionally NOT attached. Cilium overlay does not call the EC2 API for ENIs/IPs.
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", # optional: shell access through SSM
  ])

  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

# AL2023 nodeadm config: raise kubelet maxPods (EKS would otherwise compute it from the ENI/IP limit).
resource "aws_launch_template" "nodes" {
  count = var.create_nodes ? 1 : 0

  name_prefix = "${var.cluster_name}-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  user_data = base64encode(<<-EOT
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
          maxPods: ${var.max_pods}
    --BOUNDARY--
  EOT
  )
}

resource "aws_eks_node_group" "this" {
  count = var.create_nodes ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "ng-overlay"
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
    id      = aws_launch_template.nodes[0].id
    version = aws_launch_template.nodes[0].latest_version
  }

  # Keep app pods off a node until Cilium is ready. Cilium removes this taint itself.
  taint {
    key    = "node.cilium.io/agent-not-ready"
    value  = "true"
    effect = "NO_EXECUTE"
  }

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

# kube-proxy and the pod-identity agent are DaemonSets: with 0 nodes they become ACTIVE immediately,
# so they are installed in phase 1. Cilium's agent needs kube-proxy to reach the API server Service VIP
# before it can mark a node Ready.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
}

# CoreDNS is a Deployment: it needs Ready nodes (and therefore Cilium), so it is created in phase 2.
resource "aws_eks_addon" "coredns" {
  count = var.create_nodes ? 1 : 0

  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.this]
}
