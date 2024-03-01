terraform {
  required_version = ">= 1.1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.38.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 0.71.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = ">= 2.12"
    }
  }
}
