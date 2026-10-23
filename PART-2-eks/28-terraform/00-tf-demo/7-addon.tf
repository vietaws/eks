resource "aws_eks_addon" "demo" {
  cluster_name = aws_eks_cluster.demo.name
  addon_name   = "vpc-cni"
}