resource "aws_vpc" "vpctf" {
  cidr_block = "10.0.0.0/16"
  # required for EKS
  enable_dns_hostnames = true
  # required for EKS
  enable_dns_support               = true
  assign_generated_ipv6_cidr_block = false

  tags = {
    Name        = "viet-tf",
    Owner       = "VietAWS",
    Environment = "Dev"
  }
}

output "vpc_id" {
  value       = aws_vpc.vpctf.id
  description = "vpc id tf demo"
  sensitive   = false
}