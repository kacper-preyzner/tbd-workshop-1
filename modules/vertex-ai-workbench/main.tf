data "google_project" "project" {
  project_id = var.project_name
}

locals {
  zone                = "${var.region}-b"
  gce_service_account = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_service" "notebooks" {
  provider           = google
  service            = "notebooks.googleapis.com"
  disable_on_destroy = false
}


resource "google_storage_bucket" "notebook-conf-bucket" {
  #checkov:skip=CKV_GCP_62: "Bucket should log access"
  name          = "${var.project_name}-conf"
  location      = var.region
  force_destroy = true

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
}


resource "google_storage_bucket_iam_binding" "binding" {
  #checkov:skip=CKV_GCP_49: "Ensure roles do not impersonate or manage Service Accounts used at project level"
  bucket = google_storage_bucket.notebook-conf-bucket.name
  role   = "roles/storage.objectViewer"
  members = [
    "serviceAccount:${local.gce_service_account}"
  ]
}


resource "google_storage_bucket_object" "post-startup" {
  name   = "scripts/notebook_post_startup_script.sh"
  source = "${path.module}/resources/notebook_post_startup_script.sh"
  bucket = google_storage_bucket.notebook-conf-bucket.name
}



resource "google_workbench_instance" "tbd_notebook" {
  #checkov:skip=CKV2_GCP_18: "Ensure GCP network defines a firewall and does not use the default firewall"
  #checkov:skip=CKV2_GCP_21: "Ensure Vertex AI instance disks are encrypted with a Customer Managed Key (CMK)"
  depends_on = [google_project_service.notebooks]
  name       = "${var.project_name}-notebook"
  location   = local.zone
  project    = var.project_name

  gce_setup {
    machine_type = "e2-standard-2"

    network_interfaces {
      network  = var.network
      subnet   = var.subnet
      nic_type = "VIRTIO_NET"
    }

    disable_public_ip = true

    metadata = {
      vmDnsSetting        = "GlobalDefault"
      post-startup-script = "gs://${google_storage_bucket_object.post-startup.bucket}/${google_storage_bucket_object.post-startup.name}"
    }
  }

  instance_owners = [var.ai_notebook_instance_owner]
}


resource "google_project_iam_binding" "token_creator_role" {
  #checkov:skip=CKV_GCP_41: "Ensure that IAM users are not assigned the Service Account User or Service Account Token Creator roles at project level"
  #checkov:skip=CKV_GCP_49: "Ensure roles do not impersonate or manage Service Accounts used at project level"
  #checkov:skip=CKV_GCP_46: "Ensure Default Service account is not used at a project level"
  project = var.project_name
  role    = "roles/iam.serviceAccountTokenCreator"
  members = toset(["serviceAccount:${local.gce_service_account}"])

}

