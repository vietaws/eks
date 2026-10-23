# https://registry.terraform.io/providers/hashicorp/aws/latest/docs

provider "aws" {
  profile = "eks"
  region  = "ap-southeast-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # https://registry.terraform.io/providers/hashicorp/aws/latest
    }
  }
}