terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "drift_test" {
  filename = "${path.module}/drift-test.txt"
  content  = "Bu dosya Terraform tarafindan yonetiliyor. Versiyon: 1\n"
}
# yorum satırı ekle
# yorum satırı ekle
# yorum satırı ekle
