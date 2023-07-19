terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.5.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.66.0"
    }
  }
  required_version = ">= 1"
}