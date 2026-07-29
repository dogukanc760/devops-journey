packer {
  required_plugins {
    docker = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/docker"
    }
  }
}

source "docker" "golden_nginx_v2" {
  image  = "ubuntu:22.04"
  commit = true
}

build {
  name    = "golden-nginx-v2"
  sources = ["source.docker.golden_nginx_v2"]

  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get install -y nginx curl",
      "echo 'GREEN DEPLOYMENT - Versiyon 2' > /var/www/html/index.html",
      "echo 'Yeni ozellik: Blue-Green test' >> /var/www/html/index.html",
      "echo 'Build tarihi:' >> /var/www/html/index.html",
      "date >> /var/www/html/index.html"
    ]
  }

  post-processor "docker-tag" {
    repository = "golden-nginx"
    tags       = ["v2"]
  }
}
