terraform {
  required_version = ">= 1.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# OpenStack provider with explicit clouds.yaml path
provider "openstack" {
  cloud = "openstack"
}

############################
# APP-DEFAULTS (defined by the app developer)
############################

locals {
  app_name           = "online-ide"
  flavor             = "gp1.small"
  key_pair           = "" # Empty = password auth only
  enable_floating_ip = true
}

# Load Packer image from Glance
data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

# External network for floating IPs
data "openstack_networking_network_v2" "external" {
  name = var.floating_ip_pool
}

############################
# USER MANAGEMENT (CONTRACT)
############################

# Flatten users from teams - exactly as specified in the contract
locals {
  all_users = flatten([
    for team, members in var.users : [
      for member in members : {
        id       = "${team}-${split("@", member.email)[0]}"
        team     = team
        email    = member.email
        username = split("@", member.email)[0]
      }
    ]
  ])

  users_map  = { for user in local.all_users : user.id => user }
  teams_list = distinct([for user in local.all_users : user.team])
}

# Generate passwords for each user
resource "random_password" "user_passwords" {
  for_each    = local.users_map
  length      = 16
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

############################

# TEAM-BASED VMs
############################

# One port object per team
resource "openstack_networking_port_v2" "team_port" {
  for_each           = toset(local.teams_list)
  network_id         = var.network_uuid
  security_group_ids = [var.shared_secgroup_id]
}

# Deploy one VM per team, explicitly bound to its port
resource "openstack_compute_instance_v2" "team_ide" {
  for_each = toset(local.teams_list)

  name     = "${local.app_name}-${each.key}"
  image_id = data.openstack_images_image_v2.image.id
  # Per-team flavor (if selected via wizard) takes precedence over the
  # static ``local.flavor`` default. The wizard supplies a flavor UUID
  # (marker ``@openstack:flavor:id:single:team`` →
  # ``osMode = id``), so we set ``flavor_id`` instead of
  # ``flavor_name``. The two are mutually exclusive in the OpenStack
  # provider — setting both causes a conflict error on apply.
  #
  # Fallback: if no entry exists in ``var.team_flavor_ids`` for this
  # team (user left the slot empty or the variable is not set at all),
  # ``local.flavor`` is used. This keeps the default behavior
  # backward-compatible.
  flavor_id   = try(var.team_flavor_ids[each.key], null)
  flavor_name = try(var.team_flavor_ids[each.key], null) == null ? local.flavor : null
  key_pair    = local.key_pair != "" ? local.key_pair : null

  timeouts {
    create = "15m"
    delete = "15m"
  }

  network {
    port = openstack_networking_port_v2.team_port[each.key].id
  }

  # cloud-init user-data: users and groups for this team
  user_data = templatefile("${path.module}/user-data.yaml.tpl", {
    teams            = [each.key]
    users            = { for uid, u in local.users_map : uid => u if u.team == each.key }
    passwords        = { for uid, u in local.users_map : uid => random_password.user_passwords[uid].result if u.team == each.key }
    user_ports       = { for uid, u in local.users_map : uid => 8080 + local.user_indices[uid] if u.team == each.key }
    assignment_files = lookup(var.assignment_files, each.key, {})
  })

  metadata = {
    team = each.key
  }
}

############################
# FLOATING IPs
############################

# One floating IP per team VM
resource "openstack_networking_floatingip_v2" "team_fip" {
  for_each = local.enable_floating_ip ? toset(local.teams_list) : []

  pool = data.openstack_networking_network_v2.external.name
}

resource "openstack_networking_floatingip_associate_v2" "team_fip_assoc" {
  for_each = local.enable_floating_ip ? toset(local.teams_list) : []

  floating_ip = openstack_networking_floatingip_v2.team_fip[each.key].address
  port_id     = openstack_networking_port_v2.team_port[each.key].id

  depends_on = [openstack_compute_instance_v2.team_ide]
}

############################
# OUTPUT CONTRACT
############################

# User accounts per OUTPUT-CONTRACT
locals {
  # Group users by team and build index
  users_by_team = {
    for team in local.teams_list : team => [
      for uid, user in local.users_map : uid if user.team == team
    ]
  }

  # Map: user_id -> index within team (for port calculation)
  user_indices = merge([
    for team in local.teams_list : {
      for idx, uid in local.users_by_team[team] : uid => idx
    }
  ]...)

  user_accounts = {
    for uid, user in local.users_map : uid => {
      type     = "password"
      ip       = local.enable_floating_ip ? openstack_networking_floatingip_v2.team_fip[user.team].address : openstack_networking_port_v2.team_port[user.team].all_fixed_ips[0]
      port     = 8080 + local.user_indices[uid]
      username = user.username
      auth     = random_password.user_passwords[uid].result
    }
  }
}
