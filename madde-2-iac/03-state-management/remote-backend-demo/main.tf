terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "s3" {
    bucket = "terraform-state"
    key    = "state-management-demo/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "http://localhost:9010"
    }

    access_key = "minioadmin"
    secret_key = "minioadmin123"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
    use_lockfile                = true
  }
}

resource "local_file" "state_demo" {
  filename = "${path.module}/state-demo.txt"
  content  = "State artık MinIO'da tutuluyor, local'de degil. Versiyon 2.\n"
}
