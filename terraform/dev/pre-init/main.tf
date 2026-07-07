terraform {
  backend "local" {
    path = "./pre-init-state.tfstate"
  }
}

provider "aws" {
  allowed_account_ids = [var.account_id]
  region              = var.region
}

module "pre_init" {
  source = "../../modules/pre-init"

  account_id = var.account_id
  env        = var.env
  project    = var.project
  region     = var.region

  bucket_name = "terraform-state-aws-es-devops"
  table_name  = "terraform-state-aws-es-devops"
}
