terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.9.7"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.76.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.18.0"
    }
  }
  required_version = ">= 1"
}
