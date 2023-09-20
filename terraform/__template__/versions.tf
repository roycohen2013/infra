terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.7.2"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.71.0"
    }
  }
  required_version = ">= 1"
}
