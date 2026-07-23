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

# OpenStack Provider mit explizitem clouds.yaml Pfad
provider "openstack" {
  cloud = "openstack"
}

############################
# APP-DEFAULTS (vom App-Entwickler vorgegeben)
############################

locals {
  # Diese Werte sind App-spezifisch und werden vom App-Entwickler definiert
  app_name           = "online-ide"
  flavor             = "gp1.small"
  key_pair           = "" # Leer = nur Passwort-Auth
  enable_floating_ip = true
}

# Packer-Image aus Glance laden
data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

# External Network für Floating IPs
data "openstack_networking_network_v2" "external" {
  name = var.floating_ip_pool
}

############################
# USER MANAGEMENT (CONTRACT)
############################

# Flatten users from teams - EXAKT wie im Contract vorgegeben
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

# Passwörter für jeden User generieren
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

# Pro Team ein eigenes Port-Objekt
resource "openstack_networking_port_v2" "team_port" {
  for_each           = toset(local.teams_list)
  network_id         = var.network_uuid
  security_group_ids = [var.shared_secgroup_id]
}

# Pro Team eine VM deployen, die explizit an den Port gebunden ist
resource "openstack_compute_instance_v2" "team_ide" {
  for_each = toset(local.teams_list)

  name     = "${local.app_name}-${each.key}"
  image_id = data.openstack_images_image_v2.image.id
  # Per-Team-Flavor (wenn vom Wizard gewählt) hat Vorrang über den
  # statischen ``local.flavor``-Default. Der Wizard liefert eine
  # Flavor-UUID (Marker ``@openstack:flavor:id:single:team`` →
  # ``osMode = id``), also setzen wir hier ``flavor_id`` statt
  # ``flavor_name``. ``flavor_id`` und ``flavor_name`` sind beim
  # OpenStack-Provider gegenseitig exklusiv — wer beide setzt,
  # bekommt einen Konflikt-Error beim Apply.
  #
  # Fallback: Wenn für dieses Team kein Eintrag in
  # ``var.team_flavor_ids`` existiert (User hat den Slot leer
  # gelassen ODER die Variable ist überhaupt nicht gesetzt), greift
  # ``local.flavor``. Dadurch bleibt das Default-Verhalten
  # rückwärtskompatibel.
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

  # cloud-init user-data: User und Gruppen für dieses Team
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

# Floating IP pro Team-VM
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

# User Accounts gemäß OUTPUT-CONTRACT
locals {
  # Gruppiere User nach Team und erstelle Index
  users_by_team = {
    for team in local.teams_list : team => [
      for uid, user in local.users_map : uid if user.team == team
    ]
  }

  # Map: user_id -> index innerhalb des Teams (für Port-Berechnung)
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
