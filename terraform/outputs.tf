output "cluster_id" {
  description = "The ID of the Workstation Cluster."
  value       = google_workstations_workstation_cluster.cluster.id
}

output "config_id" {
  description = "The ID of the Workstation Configuration."
  value       = google_workstations_workstation_config.config.id
}

output "service_account_email" {
  description = "The email address of the Workstation Service Account."
  value       = google_service_account.workstation_sa.email
}

output "workstation_container_image" {
  description = "The deployed container image for workstations."
  value       = "${var.workstation_image_repository}/${var.workstation_image_name}:${var.workstation_image_tag}"
}

output "workstation_host" {
  description = "The hostname of the created Cloud Workstation."
  value       = google_workstations_workstation.workstation.host
}

output "workstation_url" {
  description = "The direct web URL to access Code-OSS on the workstation."
  value       = "https://${google_workstations_workstation.workstation.host}/?authuser=0"
}

output "antigravity_hub_url" {
  description = "The direct web URL to access the Standalone Antigravity Web Hub."
  value       = "https://41969-${google_workstations_workstation.workstation.host}/?authuser=0"
}
