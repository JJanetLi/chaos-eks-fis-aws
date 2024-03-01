module "core" {
  source = "./00-core"
}

module "cluster" {
  source        = "./01-cluster/chaos-cluster"
  workload_repo = module.core.codecommit_full_endpoint
}