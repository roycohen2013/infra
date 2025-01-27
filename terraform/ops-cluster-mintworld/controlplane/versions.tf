terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.60.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.16.1"
    }
  }
  required_version = ">= 1"
}
