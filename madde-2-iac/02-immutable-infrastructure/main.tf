terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_container" "golden_nginx" {
  image = "golden-nginx:v1"
  name  = "golden-nginx-instance"

  ports {
    internal = 80
    external = 8090
  }

  command = ["nginx", "-g", "daemon off;"]
}
