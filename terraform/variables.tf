variable "project_id" {
  type        = string
  description = "The GCP project ID where Cloud Workstations will be deployed."
}

variable "region" {
  type        = string
  description = "The Google Cloud region for the Workstation Cluster and Config."
  default     = "us-central1"
}

variable "network_id" {
  type        = string
  description = "The fully qualified resource name or ID of the VPC network."
}

variable "subnetwork_id" {
  type        = string
  description = "The fully qualified resource name or ID of the subnetwork (must have Private Google Access enabled)."
}

variable "workstation_cluster_id" {
  type        = string
  description = "Identifier for the Google Cloud Workstation Cluster."
  default     = "enterprise-workstations"
}

variable "workstation_config_id" {
  type        = string
  description = "Identifier for the Google Cloud Workstation Configuration."
  default     = "agy-linux-stable"
}

variable "machine_type" {
  type        = string
  description = "Compute Engine machine type for workstation instances."
  default     = "e2-standard-8"
}

variable "boot_disk_size_gb" {
  type        = number
  description = "Size of the persistent SSD mounted to /home/user in GB."
  default     = 200
}

variable "workstation_image_repository" {
  type        = string
  description = "Artifact Registry Docker repository domain and project path (e.g. us-central1-docker.pkg.dev/my-project/my-repo)."
}

variable "workstation_image_name" {
  type        = string
  description = "Container image name inside the Artifact Registry repository."
  default     = "custom-dev-image"
}

variable "workstation_image_tag" {
  type        = string
  description = "Container image tag for the custom workstation image in Artifact Registry."
  default     = "v1.6.0"
}

variable "idle_timeout_seconds" {
  type        = number
  description = "Number of seconds of inactivity before a workstation automatically stops."
  default     = 7200 # 2 hours
}
