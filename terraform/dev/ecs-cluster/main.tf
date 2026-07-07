terraform {
  backend "s3" {
    bucket         = "terraform-state-aws-es-devops"
    dynamodb_table = "terraform-state-aws-es-devops"
    encrypt        = true
    key            = "dev-cluster-ecs.tfstate"
    region         = "eu-central-1"
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "terraform-state-aws-es-devops"
    key    = "dev-network.tfstate"
    region = var.region
  }
}

provider "aws" {
  allowed_account_ids = [var.account_id]
  region              = var.region
}

module "ecs-cluster" {
  source = "../../modules/ecs-cluster"

  account_id = var.account_id
  env        = var.env
  project    = var.project
  region     = var.region

  docker_image_url_es = "004571937517.dkr.ecr.eu-central-1.amazonaws.com/udemy-aws-es-node:latest"
}
