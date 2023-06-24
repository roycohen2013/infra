# This data source depends on the stackscript resource
# which is created in terraform/ops-stackscripts/main.tf
data "linode_stackscripts" "cloudinit_scripts" {
  filter {
    name   = "label"
    values = ["CloudInit"]
  }
}

# This data source depends on the domain resource
# which is created in terraform/ops-dns/main.tf
data "linode_domain" "ops_dns_domain" {
  domain = "freecodecamp.net"
}

resource "linode_instance" "ops_o11y_leaders" {
  count  = var.leader_node_count
  label  = "ops-vm-o11y-ldr-${count.index + 1}"
  group  = "o11y-ldr"
  region = var.region
  type   = "g6-standard-2"

  tags = ["ops", "o11y", "o11y_leader"] # tags should use underscores for Ansible compatibility
}

resource "linode_instance_disk" "ops_o11y_leaders_disk__boot" {
  count     = var.leader_node_count
  label     = "ops-vm-o11y-ldr-${count.index + 1}-boot"
  linode_id = linode_instance.ops_o11y_leaders[count.index].id
  size      = linode_instance.ops_o11y_leaders[count.index].specs.0.disk

  image     = var.image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = filebase64("${path.root}/cloud-init--userdata.yml")
  }
}

resource "linode_instance_config" "ops_o11y_leaders_config" {
  count     = var.leader_node_count
  label     = "ops-vm-o11y-ldr-config"
  linode_id = linode_instance.ops_o11y_leaders[count.index].id

  devices {
    sda {
      disk_id = linode_instance_disk.ops_o11y_leaders_disk__boot[count.index].id
    }
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "o11y-vlan"
    # This results in IPAM address like 10.0.0.11/24, 10.0.0.12/24, etc.
    ipam_address = "${cidrhost("10.0.0.0/8", 10 + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.ops_o11y_leaders[count.index].ip_address
  }

  provisioner "remote-exec" {
    inline = [
      # Disable password authentication; users can only connect with an SSH key.
      "sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config",
      "echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config",
      # Set the hostname.
      "hostnamectl set-hostname ldr-${count.index + 1}.o11y.${data.linode_domain.ops_dns_domain.domain}"
    ]
  }

  helpers {
    updatedb_disabled = true
  }

  booted = true
}

resource "linode_domain_record" "ops_o11y_leaders_records" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "ldr-${count.index + 1}.o11y"
  record_type = "A"
  target      = linode_instance.ops_o11y_leaders[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "ops_o11y_leaders_records__public" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.ldr-${count.index + 1}.o11y"
  record_type = "A"
  target      = linode_instance.ops_o11y_leaders[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "ops_o11y_leaders_records__private" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.ldr-${count.index + 1}.o11y"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.ops_o11y_leaders_config[count.index].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_instance" "ops_o11y_workers" {
  count  = var.worker_node_count
  label  = "ops-vm-o11y-wkr-${count.index + 1}"
  group  = "o11y-wkr"
  region = var.region
  type   = "g6-standard-2"

  tags = ["ops", "o11y", "o11y_worker"]
}

resource "linode_instance_disk" "ops_o11y_workers_disk__boot" {
  count     = var.worker_node_count
  label     = "ops-vm-o11y-wkr-${count.index + 1}-boot"
  linode_id = linode_instance.ops_o11y_workers[count.index].id
  size      = linode_instance.ops_o11y_workers[count.index].specs.0.disk

  image     = var.image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = filebase64("${path.root}/cloud-init--userdata.yml")
  }
}

resource "linode_instance_config" "ops_o11y_workers_config" {
  count     = var.worker_node_count
  label     = "ops-vm-o11y-wkr-config"
  linode_id = linode_instance.ops_o11y_workers[count.index].id

  devices {
    sda {
      disk_id = linode_instance_disk.ops_o11y_workers_disk__boot[count.index].id
    }
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "o11y-vlan"
    # This results in IPAM address like 10.0.0.21/24, 10.0.0.22/24, etc.
    ipam_address = "${cidrhost("10.0.0.0/8", 20 + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.ops_o11y_workers[count.index].ip_address
  }

  provisioner "remote-exec" {
    inline = [
      # Update the system.
      "apt-get update -qq",
      # Disable password authentication; users can only connect with an SSH key.
      "sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config",
      "echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config",
      # Set the hostname.
      "hostnamectl set-hostname wkr-${count.index + 1}.o11y.${data.linode_domain.ops_dns_domain.domain}"
    ]
  }

  helpers {
    updatedb_disabled = true
  }

  booted = true
}

resource "linode_domain_record" "ops_o11y_workers_records" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "wkr-${count.index + 1}.o11y"
  record_type = "A"
  target      = linode_instance.ops_o11y_workers[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "ops_o11y_workers_records__public" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.wkr-${count.index + 1}.o11y"
  record_type = "A"
  target      = linode_instance.ops_o11y_workers[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "ops_o11y_workers_records__private" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.wkr-${count.index + 1}.o11y"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.ops_o11y_workers_config[count.index].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_firewall" "ops_o11y_firewall" {
  label = "ops-fw-o11y"

  inbound {
    label    = "allow-ssh"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound_policy = "DROP"

  # outbound { }

  outbound_policy = "ACCEPT"

  linodes = flatten([
    [for i in linode_instance.ops_o11y_leaders : i.id],
    [for i in linode_instance.ops_o11y_workers : i.id],
  ])
}