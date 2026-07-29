terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

variable "active_version" {
  description = "Trafiğin yönlendirileceği versiyon: blue veya green"
  type        = string
  default     = "blue"
}

resource "docker_network" "app_net" {
  name = "bluegreen-net"
}

# Blue = golden-nginx:v1, her zaman ayakta
resource "docker_container" "blue" {
  image = "golden-nginx:v1"
  name  = "app-blue"
  command = ["nginx", "-g", "daemon off;"]

  networks_advanced {
    name = docker_network.app_net.name
  }
}

# Green = golden-nginx:v2, her zaman ayakta
resource "docker_container" "green" {
  image = "golden-nginx:v2"
  name  = "app-green"
  command = ["nginx", "-g", "daemon off;"]

  networks_advanced {
    name = docker_network.app_net.name
  }
}

# Proxy: hangi versiyona yönlendireceğini "command" içinde taşıyor.
# var.active_version değişince bu attribute değişir, Terraform
# container'ı yeniden oluşturur (ForceNew) — trafik kaydırma işlemi
# aslında bir "replace" (immutable) işlemi olarak gerçekleşiyor.
resource "docker_container" "proxy" {
  image = "nginx:alpine"
  name  = "bg-proxy"

  command = [
    "sh", "-c",
    "printf 'events{}\\nhttp{ server { listen 80; location / { proxy_pass http://app-${var.active_version}:80; } } }\\n' > /etc/nginx/nginx.conf && nginx -g 'daemon off;'"
  ]

  ports {
    internal = 80
    external = 8100
  }

  networks_advanced {
    name = docker_network.app_net.name
  }

  depends_on = [docker_container.blue, docker_container.green]
}
