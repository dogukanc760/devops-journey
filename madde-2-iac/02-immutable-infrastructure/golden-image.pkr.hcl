packer {
  required_plugins {
    docker = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/docker"
    }
  }
}

source "docker" "golden_nginx" {
  image  = "ubuntu:22.04"
  commit = true
}

build {
  name    = "golden-nginx"
  sources = ["source.docker.golden_nginx"]

  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get install -y nginx curl",
      "echo 'Golden Image - Immutable Infrastructure Demo' > /var/www/html/index.html",
      "echo 'Build tarihi:' >> /var/www/html/index.html",
      "date >> /var/www/html/index.html"
    ]
  }

  post-processor "docker-tag" {
    repository = "golden-nginx"
    tags       = ["v1"]
  }
}
