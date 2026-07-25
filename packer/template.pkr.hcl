packer {
  required_plugins {
    openstack = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/openstack"
    }
  }
}

############################
# APP-DEFAULTS (defined by the app developer)
############################

locals {
  cloud = "openstack"

  provision_script        = "scripts/provision.sh"
  source_image_name       = "Ubuntu 22.04"
  flavor                  = "gp1.small"
  ssh_username            = "ubuntu"
  ssh_timeout             = "20m"
  use_blockstorage_volume = false # Recommended: false (prevents dangling volumes)
  volume_size             = 10
  use_floating_ip         = false # Build VM does not need a floating IP
}

source "openstack" "image" {
  cloud             = local.cloud
  image_name        = var.image_name
  source_image_name = local.source_image_name
  flavor            = local.flavor
  networks          = var.networks

  security_groups = var.security_groups

  use_blockstorage_volume = local.use_blockstorage_volume
  volume_size             = local.volume_size

  use_floating_ip = local.use_floating_ip

  ssh_ip_version = "4"
  ssh_timeout    = local.ssh_timeout
  ssh_username   = local.ssh_username
}

build {
  sources = ["source.openstack.image"]

  # Wait for cloud-init to complete before provisioning
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init...'",
      "cloud-init status --wait || true",
      "echo 'Cloud-init ready'"
    ]
  }

  # Main provisioning
  provisioner "shell" {
    script = local.provision_script
    # Retry on transient network errors (apt-get)
    max_retries = 3
  }
}
