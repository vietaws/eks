output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "primary_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "pod_subnet_ids" {
  value = aws_subnet.pods[*].id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region}${var.profile == null ? "" : " --profile ${var.profile}"}"
}

# One ENIConfig per AZ, named after the AZ (ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone).
# Pod ENIs reuse the cluster security group so the ALB / node rules keep working.
output "eniconfig_manifest" {
  value = join("---\n", [
    for i, az in local.azs : yamlencode({
      apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
      kind       = "ENIConfig"
      metadata   = { name = az }
      spec = {
        subnet         = aws_subnet.pods[i].id
        securityGroups = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
      }
    })
  ])
}
