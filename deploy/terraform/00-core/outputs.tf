
output "managed_prometheus_workspace_endpoint" {
  description = "Amazon Managed Prometheus workspace endpoint"
  value       = local.amp_ws_endpoint
}

output "managed_prometheus_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID"
  value       = local.amp_ws_id
}

output "managed_prometheus_workspace_region" {
  description = "Amazon Managed Prometheus workspace region"
  value       = local.amp_ws_region
}

output "managed_grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace endpoint"
  value       = local.amg_ws_endpoint
}

output "managed_grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = local.amg_ws_id
}

output "codecommit_full_endpoint" {
  description = "Full endpoint to codecommit including credentials"
  value       = "https://${aws_iam_service_specific_credential.credentials.service_user_name}:${aws_iam_service_specific_credential.credentials.service_password}@git-codecommit.${local.amp_ws_region}.amazonaws.com/v1/repos/${aws_codecommit_repository.chaos_gitops_repository.repository_name}"
}
