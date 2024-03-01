output "codecommit_full_endpoint" {
  description = "Full endpoint to codecommit"
  value       = "${module.core.codecommit_full_endpoint}"
  sensitive = true
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.cluster.configure_kubectl
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = "${module.cluster.rds_instance_endpoint}"
  sensitive = true
}

output "rds_username" {
  description = "RDS username"
  value       = "${module.cluster.rds_instance_username}"
  sensitive = true
}

output "rds_password_secrets_manager_arn" {
  description = "RDS password AWS Secrets Manager ARN"
  value       = "${module.cluster.secrets_manager_secret_arn}"
}