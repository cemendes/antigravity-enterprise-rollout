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
