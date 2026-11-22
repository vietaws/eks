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
  default = "vietvn-secondary"
}

variable "k8s_version" {
  type    = string
  default = "1.37"
}

# Fixed to t3.medium: the max-pods numbers in the README/locals assume 3 ENIs x 6 IPv4 per ENI.
variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_count" {
  type    = number
  default = 2
}

# Demo stage, applied one after the other (see README):
#   0 = default VPC CNI               -> 17 pods/node (formula 3*(6-1)+2), pods use primary-subnet IPs
#   1 = custom networking             -> pods use the 100.64.0.0/16 secondary CIDR, 12 pods/node ((3-1)*(6-1)+2)
#   2 = custom networking + prefix delegation -> pods use /28 prefixes of the secondary CIDR, 110 pods/node
variable "stage" {
  type    = number
  default = 0

  validation {
    condition     = contains([0, 1, 2], var.stage)
    error_message = "stage must be 0, 1 or 2."
  }
}
