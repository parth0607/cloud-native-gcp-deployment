/**
 * Copyright 2023 Google LLC
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

// This file was automatically generated from a template in ./autogen/main

/******************************************
  Get available zones in region
 *****************************************/
data "google_compute_zones" "available" {
  provider = google

  project = var.project_id
  region  = var.region
}

// data "random_shuffle1" "available_zones" {
//   input        = data.google_compute_zones.available.names
//   result_count = 3
// }

locals {
  // location
  location = var.regional ? var.region : data.google_compute_zones.available.names[0]
  // region   = var.regional ? var.region : join("-", slice(split("-", data.google_compute_zones.available.names[0]), 0, 2))
  // for regional cluster - use var.zones if provided, use available otherwise, for zonal cluster use var.zones with first element extracted
  // node_locations = var.regional ? coalescelist(compact(var.zones), slice(data.google_compute_zones.available.names, 0, 3)) : slice(var.zones, 0, length(var.zones))
  node_locations = var.regional ? coalescelist(compact(var.zones), slice(data.google_compute_zones.available.names, 0, 3)) : null
  zones          = var.regional ? local.node_locations : var.zones

  // Kubernetes version
  master_version_regional = var.kubernetes_version != "latest" ? var.kubernetes_version : data.google_container_engine_versions.region.latest_master_version
  master_version_zonal    = var.kubernetes_version != "latest" ? var.kubernetes_version : data.google_container_engine_versions.zone.latest_master_version
  master_version          = var.regional ? local.master_version_regional : local.master_version_zonal

  // Build a map of maps of node pools from a list of objects
  node_pool_names = [for np in toset(var.node_pools) : np.name]
  node_pools      = zipmap(local.node_pool_names, tolist(toset(var.node_pools)))



  custom_kube_dns_config      = length(keys(var.stub_domains)) > 0
  upstream_nameservers_config = length(var.upstream_nameservers) > 0
  network_project_id          = var.network_project_id != "" ? var.network_project_id : var.project_id
  zone_count                  = length(var.zones)
  cluster_type                = var.regional ? "regional" : "zonal"
  // auto upgrade by defaults only for regional cluster as long it has multiple masters versus zonal clusters have only have a single master so upgrades are more dangerous.
  default_auto_upgrade = var.regional ? true : false
  release_channel      = var.release_channel != null ? [{ channel : var.release_channel }] : []

  cluster_subnet_cidr       = var.add_cluster_firewall_rules ? data.google_compute_subnetwork.gke_subnetwork[0].ip_cidr_range : null
  cluster_alias_ranges_cidr = var.add_cluster_firewall_rules ? { for range in toset(data.google_compute_subnetwork.gke_subnetwork[0].secondary_ip_range) : range.range_name => range.ip_cidr_range } : {}

  cluster_network_policy = var.network_policy ? [{
    enabled  = true
    provider = var.network_policy_provider
    }] : [{
    enabled  = false
    provider = null
  }]


  gke_backup_agent_config       = var.gke_backup_agent_config ? [{ enabled = true }] : [{ enabled = false }]
  cluster_output_name           = google_container_cluster.primary.name
  cluster_output_regional_zones = google_container_cluster.primary.node_locations
  cluster_output_zonal_zones    = local.zone_count > 1 ? slice(var.zones, 1, local.zone_count) : []
  cluster_output_zones          = local.cluster_output_regional_zones

  cluster_endpoint           = (var.enable_private_nodes && length(google_container_cluster.primary.private_cluster_config) > 0) ? (var.deploy_using_private_endpoint ? google_container_cluster.primary.private_cluster_config.0.private_endpoint : google_container_cluster.primary.private_cluster_config.0.public_endpoint) : google_container_cluster.primary.endpoint
  cluster_peering_name       = (var.enable_private_nodes && length(google_container_cluster.primary.private_cluster_config) > 0) ? google_container_cluster.primary.private_cluster_config.0.peering_name : null
  cluster_endpoint_for_nodes = var.master_ipv4_cidr_block
  cluster_authenticator_security_group = var.authenticator_security_group == null ? [] : [{
    security_group = var.authenticator_security_group
  }]

  cluster_output_master_auth                        = concat(google_container_cluster.primary.*.master_auth, [])
  cluster_output_master_version                     = google_container_cluster.primary.master_version
  cluster_output_min_master_version                 = google_container_cluster.primary.min_master_version
  cluster_output_logging_service                    = google_container_cluster.primary.logging_service
  cluster_output_monitoring_service                 = google_container_cluster.primary.monitoring_service
  cluster_output_network_policy_enabled             = google_container_cluster.primary.addons_config.0.network_policy_config.0.disabled
  cluster_output_http_load_balancing_enabled        = google_container_cluster.primary.addons_config.0.http_load_balancing.0.disabled
  cluster_output_horizontal_pod_autoscaling_enabled = google_container_cluster.primary.addons_config.0.horizontal_pod_autoscaling.0.disabled
  # cluster_output_gcp_filestore_csi_driver_enabled   = google_container_cluster.primary.addons_config.0.gcp_filestore_csi_driver.0.enabled

  master_authorized_networks_config = length(var.master_authorized_networks) == 0 ? [] : [{
    cidr_blocks : var.master_authorized_networks
  }]

  # cluster_output_node_pools_names    = concat([for np in google_container_node_pool.pools : np.name], [""])
  # cluster_output_node_pools_versions = concat([for np in google_container_node_pool.pools : np.version], [""])

  cluster_master_auth_list_layer1 = local.cluster_output_master_auth
  cluster_master_auth_list_layer2 = local.cluster_master_auth_list_layer1[0]
  cluster_master_auth_map         = local.cluster_master_auth_list_layer2[0]

  cluster_location = google_container_cluster.primary.location
  cluster_region   = var.regional ? var.region : join("-", slice(split("-", local.cluster_location), 0, 2))
  cluster_zones    = sort(local.cluster_output_zones)

  cluster_name               = local.cluster_output_name
  cluster_network_tag        = "gke-${var.name}"
  cluster_ca_certificate     = local.cluster_master_auth_map["cluster_ca_certificate"]
  cluster_master_version     = local.cluster_output_master_version
  cluster_min_master_version = local.cluster_output_min_master_version
  cluster_logging_service    = local.cluster_output_logging_service
  cluster_monitoring_service = local.cluster_output_monitoring_service
  # cluster_node_pools_names                   = local.cluster_output_node_pools_names
  # cluster_node_pools_versions                = local.cluster_output_node_pools_versions
  cluster_network_policy_enabled             = !local.cluster_output_network_policy_enabled
  cluster_http_load_balancing_enabled        = !local.cluster_output_http_load_balancing_enabled
  cluster_horizontal_pod_autoscaling_enabled = !local.cluster_output_horizontal_pod_autoscaling_enabled

}

/******************************************
  Get available container engine versions
 *****************************************/
data "google_container_engine_versions" "region" {
  location = local.location
  project  = var.project_id
}

data "google_container_engine_versions" "zone" {
  // Work around to prevent a lack of zone declaration from causing regional cluster creation from erroring out due to error
  //
  //     data.google_container_engine_versions.zone: Cannot determine zone: set in this resource, or set provider-level zone.
  //
  location = local.zone_count == 0 ? data.google_compute_zones.available.names[0] : var.zones[0]
  project  = var.project_id
}
