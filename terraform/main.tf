provider "google" {
  project = var.project_id
  region  = var.region
}

# Dedicated Service Account attached to Workstation VMs
resource "google_service_account" "workstation_sa" {
  account_id   = "workstation-runner-sa"
  display_name = "Cloud Workstations Runner Service Account"
  description  = "Identity for Cloud Workstations to pull custom images and write logs"
}

# Grant Artifact Registry Reader to pull the custom workstation container image
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

# Grant Log Writer for Cloud Operations logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workstation_sa.email}"
}

# Google Cloud Workstation Cluster
resource "google_workstations_workstation_cluster" "cluster" {
  workstation_cluster_id = var.workstation_cluster_id
  network                = var.network_id
  subnetwork             = var.subnetwork_id
  location               = var.region

  labels = {
    managed_by = "terraform"
    env        = "production"
  }
}

# Google Cloud Workstation Configuration with Pre-Baked Antigravity Image
resource "google_workstations_workstation_config" "config" {
  workstation_cluster_id = google_workstations_workstation_cluster.cluster.workstation_cluster_id
  workstation_config_id  = var.workstation_config_id
  location               = var.region
  idle_timeout           = "${var.idle_timeout_seconds}s"

  host {
    gce_instance {
      machine_type                = var.machine_type
      service_account             = google_service_account.workstation_sa.email
      disable_public_ip_addresses = true

      shielded_instance_config {
        enable_secure_boot          = true
        enable_vtpm                 = true
        enable_integrity_monitoring = true
      }
    }
  }

  persistent_directories {
    gce_pd {
      size_gb        = var.boot_disk_size_gb
      disk_type      = "pd-balanced"
      reclaim_policy = "RETAIN"
    }
    mount_path = "/home"
  }

  container {
    image = "${var.workstation_image_repository}/${var.workstation_image_name}:${var.workstation_image_tag}"
  }

  labels = {
    managed_by = "terraform"
    product    = "antigravity"
  }
}

# Individual Developer Workstation Instance
resource "google_workstations_workstation" "workstation" {
  workstation_id         = var.workstation_id
  workstation_config_id  = google_workstations_workstation_config.config.workstation_config_id
  workstation_cluster_id = google_workstations_workstation_cluster.cluster.workstation_cluster_id
  location               = var.region

  labels = {
    managed_by = "terraform"
    env        = "production"
  }
}
