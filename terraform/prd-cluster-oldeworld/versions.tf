terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.25.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.83.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.38.0"
    }
  }
  required_version = ">= 1"
}
