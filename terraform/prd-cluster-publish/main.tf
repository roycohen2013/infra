# This data source depends on the stackscript resource
# which is created in terraform/ops-stackscripts/main.tf
data "linode_stackscripts" "cloudinit_scripts" {
  filter {
    name   = "label"
    values = ["CloudInitfreeCodeCamp"]
  }
  filter {
    name   = "is_public"
    values = ["false"]
  }
}

# This data source depends on the domain resource
# which is created in terraform/ops-dns/main.tf
data "linode_domain" "ops_dns_domain" {
  domain = "freecodecamp.net"
}

data "hcp_packer_image" "linode_ubuntu" {
  bucket_name    = "linode-ubuntu"
  channel        = "latest"
  cloud_provider = "linode"
  region         = "us-east"
}

resource "linode_instance" "prd_publish_leaders" {
  count  = var.leader_node_count
  label  = "prd-vm-publish-ldr-${count.index + 1}"
  group  = "publish_leader" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-2"

  private_ip = true

  tags = ["prd", "publish", "publish_leader"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_instance_disk" "prd_publish_leaders_disk__boot" {
  count     = var.leader_node_count
  label     = "prd-vm-publish-ldr-${count.index + 1}-boot"
  linode_id = linode_instance.prd_publish_leaders[count.index].id
  size      = linode_instance.prd_publish_leaders[count.index].specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "ldr-${count.index + 1}.publish.prd.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "prd_publish_leaders_config" {
  count     = var.leader_node_count
  label     = "prd-vm-publish-ldr-config"
  linode_id = linode_instance.prd_publish_leaders[count.index].id

  devices {
    sda {
      disk_id = linode_instance_disk.prd_publish_leaders_disk__boot[count.index].id
    }
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "publish-vlan"
    # This results in IPAM address like 10.0.0.11/24, 10.0.0.12/24, etc.
    ipam_address = "${cidrhost("10.0.0.0/8", 10 + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.prd_publish_leaders[count.index].ip_address
  }

  # All of the provisioning should be done via cloud-init.
  # This is just to setup the reboot.
  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish.
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "echo Current hostname...; hostname",
      "shutdown -r +1 'Terraform: Rebooting to apply hostname change in 1 min.'"
    ]
  }

  # This run is a hack to trigger the reboot,
  # which may fail otherwise in the previous step.
  provisioner "remote-exec" {
    inline = [
      "uptime"
    ]
  }

  helpers {
    updatedb_disabled = true
  }

  booted = true
}

resource "linode_domain_record" "prd_publish_leaders_dnsrecord__vlan" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "ldr-${count.index + 1}.publish.prd"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.prd_publish_leaders_config[count.index].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_publish_leaders_dnsrecord__public" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.ldr-${count.index + 1}.publish.prd.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.prd_publish_leaders[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_publish_leaders_dnsrecord__private" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.ldr-${count.index + 1}.publish.prd"
  record_type = "A"
  target      = linode_instance.prd_publish_leaders[count.index].private_ip_address
  ttl_sec     = 120
}

resource "linode_instance" "prd_publish_workers" {
  count  = var.worker_node_count
  label  = "prd-vm-publish-wkr-${count.index + 1}"
  group  = "publish_worker" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-4"

  private_ip = true

  tags = ["prd", "publish", "publish_worker"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_instance_disk" "prd_publish_workers_disk__boot" {
  count     = var.worker_node_count
  label     = "prd-vm-publish-wkr-${count.index + 1}-boot"
  linode_id = linode_instance.prd_publish_workers[count.index].id
  size      = linode_instance.prd_publish_workers[count.index].specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "wkr-${count.index + 1}.publish.prd.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "prd_publish_workers_config" {
  count     = var.worker_node_count
  label     = "prd-vm-publish-wkr-config"
  linode_id = linode_instance.prd_publish_workers[count.index].id

  devices {
    sda {
      disk_id = linode_instance_disk.prd_publish_workers_disk__boot[count.index].id
    }
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "publish-vlan"
    # This results in IPAM address like 10.0.0.21/24, 10.0.0.22/24, etc.
    ipam_address = "${cidrhost("10.0.0.0/8", 20 + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.prd_publish_workers[count.index].ip_address
  }

  # All of the provisioning should be done via cloud-init.
  # This is just to setup the reboot.
  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish.
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "echo Current hostname...; hostname",
      "shutdown -r +1 'Terraform: Rebooting to apply hostname change in 1 min.'"
    ]
  }

  # This run is a hack to trigger the reboot,
  # which may fail otherwise in the previous step.
  provisioner "remote-exec" {
    inline = [
      "uptime"
    ]
  }

  helpers {
    updatedb_disabled = true
  }

  booted = true
}

resource "linode_domain_record" "prd_publish_workers_dnsrecord__vlan" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "wkr-${count.index + 1}.publish.prd"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.prd_publish_workers_config[count.index].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_publish_workers_dnsrecord__public" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.wkr-${count.index + 1}.publish.prd.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.prd_publish_workers[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_publish_workers_dnsrecord__private" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.wkr-${count.index + 1}.publish.prd"
  record_type = "A"
  target      = linode_instance.prd_publish_workers[count.index].private_ip_address
  ttl_sec     = 120
}

resource "linode_firewall" "prd_publish_firewall" {
  label = "prd-fw-publish"

  inbound {
    label    = "allow-ssh_from-anywhere"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-tcp_within-cluster"
    ports    = "1-65535"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4 = flatten([
      [for i in linode_instance.prd_publish_leaders : "${i.private_ip_address}/32"],
      [for i in linode_instance.prd_publish_workers : "${i.private_ip_address}/32"]
    ])
  }

  inbound {
    label    = "allow-udp_within-cluster"
    ports    = "1-65535"
    protocol = "UDP"
    action   = "ACCEPT"
    ipv4 = flatten([
      [for i in linode_instance.prd_publish_leaders : "${i.private_ip_address}/32"],
      [for i in linode_instance.prd_publish_workers : "${i.private_ip_address}/32"]
    ])
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    [for i in linode_instance.prd_publish_leaders : i.id],
    [for i in linode_instance.prd_publish_workers : i.id],
  ])
}
