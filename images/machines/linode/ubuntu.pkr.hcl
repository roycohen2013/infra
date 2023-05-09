packer {
  required_plugins {
    linode = {
      version = ">= 1.0.5"
      source  = "github.com/linode/linode"
    }
  }
}

variable "scripts_dir" { default = "images/machines/linode/scripts" }

locals { image_version = "${formatdate("YYYYMMDD.hhmm", timestamp())}" }

variable "linode_token" {
  type = string
  default = env("LINODE_TOKEN")

  validation {
    condition = length(var.linode_token) > 0
    error_message = "The LINODE_TOKEN environment variable must be set or the -var linode_token=xxxxx must be used to set the token value."
  }
}

variable "linode_instance_type"     { default = "g6-dedicated-2" }
variable "linode_region"            { default = "us-east" }
variable "linode_image"             { default = "linode/ubuntu20.04" }
variable "linode_image_description" { default = "Ubuntu 20.04 LTS" }
variable "linode_os_version"        { default = "20.04" }
variable "linode_os_flavor"         { default = "ubuntu" }

source "linode" "ubuntu" {
  linode_token      = "${var.linode_token}"
  image             = var.linode_image
  region            = var.linode_region
  instance_type     = var.linode_instance_type
  image_label       = "ami-${var.linode_os_flavor}-${var.linode_os_version}-${local.image_version}"
  instance_label    = "pkr-${var.linode_os_flavor}-${var.linode_os_version}-${local.image_version}"
  image_description = var.linode_image_description
  ssh_username      = "root"
}

build {
  name = "ubuntu"
  sources = ["source.linode.ubuntu"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  provisioner "ansible" {
    playbook_file = "${var.scripts_dir}/ansible/install-common.yml"
    user = "root"
    use_proxy = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False"
    ]
    extra_arguments = [
      "-v"
    ]
  }

  provisioner "ansible" {
    playbook_file = "${var.scripts_dir}/ansible/install-docker.yml"
    user = "root"
    use_proxy = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False"
    ]
    extra_arguments = [
      "-v"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
