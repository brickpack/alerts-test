terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.22.2"
    }
  }
}

provider "grafana" {
  url  = "http://localhost:3000"
  auth = "admin:admin"  # Basic auth for local testing
} 