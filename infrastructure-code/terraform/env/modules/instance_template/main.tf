/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#########
# Locals
#########

locals {
  source_image         = var.source_image != "" ? var.source_image : "centos-7-v20201112"
  source_image_family  = var.source_image_family != "" ? var.source_image_family : "centos-7"
  source_image_project = var.source_image_project != "" ? var.source_image_project : "centos-cloud"

  boot_disk = [
    {
      source_image = var.source_image != "" ? format("${local.source_image_project}/${local.source_image}") : format("${local.source_image_project}/${local.source_image_family}")
      disk_size_gb = var.disk_size_gb
      disk_type    = var.disk_type
      disk_labels  = var.disk_labels
      auto_delete  = var.auto_delete
      boot         = "true"
    },
  ]

  all_disks = concat(local.boot_disk, var.additional_disks)

  # NOTE: Even if all the shielded_instance_config or confidential_instance_config
  # values are false, if the config block exists and an unsupported image is chosen,
  # the apply will fail so we use a single-value array with the default value to
  # initialize the block only if it is enabled.
  shielded_vm_configs          = var.enable_shielded_vm ? [true] : []
  confidential_instance_config = var.enable_confidential_vm ? [true] : []

  gpu_enabled            = var.gpu != null
  alias_ip_range_enabled = var.alias_ip_range != null
  on_host_maintenance = (
    var.preemptible || var.enable_confidential_vm || local.gpu_enabled
    ? "TERMINATE"
    : var.on_host_maintenance
  )
  automatic_restart = (
    # must be false when preemptible is true
    var.preemptible ? false : var.automatic_restart
  )
}

####################
# Instance Template
####################
resource "google_compute_instance_template" "tpl" {
  name_prefix             = var.name_prefix
  project                 = var.project_id
  machine_type            = var.machine_type
  labels                  = var.labels
  metadata                = var.metadata
  tags                    = var.tags
  can_ip_forward          = var.can_ip_forward
  metadata_startup_script = var.startup_script
  region                  = var.region
  min_cpu_platform        = var.min_cpu_platform
  dynamic "disk" {
    for_each = local.all_disks
    content {
      auto_delete  = lookup(disk.value, "auto_delete", null)
      boot         = lookup(disk.value, "boot", null)
      device_name  = lookup(disk.value, "device_name", null)
      disk_name    = lookup(disk.value, "disk_name", null)
      disk_size_gb = lookup(disk.value, "disk_size_gb", lookup(disk.value, "disk_type", null) == "local-ssd" ? "375" : null)
      disk_type    = lookup(disk.value, "disk_type", null)
      interface    = lookup(disk.value, "interface", lookup(disk.value, "disk_type", null) == "local-ssd" ? "NVME" : null)
      mode         = lookup(disk.value, "mode", null)
      source       = lookup(disk.value, "source", null)
      source_image = lookup(disk.value, "source_image", null)
      type         = lookup(disk.value, "disk_type", null) == "local-ssd" ? "SCRATCH" : "PERSISTENT"
      labels       = lookup(disk.value, "disk_labels", null)

      dynamic "disk_encryption_key" {
        for_each = compact([var.disk_encryption_key == null ? null : 1])
        content {
          kms_key_self_link = var.disk_encryption_key
        }
      }
    }
  }

  dynamic "service_account" {
    for_each = var.service_account == null ? [] : [var.service_account]
    content {
      email  = lookup(service_account.value, "email", null)
      scopes = lookup(service_account.value, "scopes", null)
    }
  }

  network_interface {
    network            = var.network
    subnetwork         = var.subnetwork
    subnetwork_project = var.subnetwork_project
    network_ip         = length(var.network_ip) > 0 ? var.network_ip : null
    dynamic "access_config" {
      for_each = var.access_config
      content {
        nat_ip       = access_config.value.nat_ip
        network_tier = access_config.value.network_tier
      }
    }
    dynamic "alias_ip_range" {
      for_each = local.alias_ip_range_enabled ? [var.alias_ip_range] : []
      content {
        ip_cidr_range         = alias_ip_range.value.ip_cidr_range
        subnetwork_range_name = alias_ip_range.value.subnetwork_range_name
      }
    }
  }

  dynamic "network_interface" {
    for_each = var.additional_networks
    content {
      network            = network_interface.value.network
      subnetwork         = network_interface.value.subnetwork
      subnetwork_project = network_interface.value.subnetwork_project
      network_ip         = length(network_interface.value.network_ip) > 0 ? network_interface.value.network_ip : null
      dynamic "access_config" {
        for_each = network_interface.value.access_config
        content {
          nat_ip       = access_config.value.nat_ip
          network_tier = access_config.value.network_tier
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = "true"
  }

  scheduling {
    preemptible         = var.preemptible
    automatic_restart   = local.automatic_restart
    on_host_maintenance = local.on_host_maintenance
  }

  advanced_machine_features {
    enable_nested_virtualization = var.enable_nested_virtualization
    threads_per_core             = var.threads_per_core
  }

  dynamic "shielded_instance_config" {
    for_each = local.shielded_vm_configs
    content {
      enable_secure_boot          = lookup(var.shielded_instance_config, "enable_secure_boot", shielded_instance_config.value)
      enable_vtpm                 = lookup(var.shielded_instance_config, "enable_vtpm", shielded_instance_config.value)
      enable_integrity_monitoring = lookup(var.shielded_instance_config, "enable_integrity_monitoring", shielded_instance_config.value)
    }
  }

  confidential_instance_config {
    enable_confidential_compute = var.enable_confidential_vm
  }

  dynamic "guest_accelerator" {
    for_each = local.gpu_enabled ? [var.gpu] : []
    content {
      type  = guest_accelerator.value.type
      count = guest_accelerator.value.count
    }
  }
}
