terraform {
  backend "s3" {
    bucket         = "terraform-state-aws-es-devops"
    dynamodb_table = "terraform-state-aws-es-devops"
    encrypt        = true
    key            = "dev-ec2-ecs.tfstate"
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

data "terraform_remote_state" "iam" {
  backend = "s3"

  config = {
    bucket = "terraform-state-aws-es-devops"
    key    = "dev-iam-profile-ecs.tfstate"
    region = var.region
  }
}

provider "aws" {
  allowed_account_ids = [var.account_id]
  region              = var.region
}

module "ecs-ec2" {
  for_each = {
    app-a = {
      private_ip           = "172.27.72.50",
      az                   = "eu-central-1a",
      instance_type        = "t3a.small",
    },
    app-b = {
      private_ip           = "172.27.72.100",
      az                   = "eu-central-1b",
      instance_type        = "t3a.small"
    },
    app-c = {
      private_ip           = "172.27.72.150",
      az                   = "eu-central-1c",
      instance_type        = "t3a.small"
    },
  }

  source = "../../modules/ecs-ec2"

  account_id = var.account_id
  env        = var.env
  project    = var.project
  region     = var.region

  private_ip           = each.value.private_ip
  volume_size          = 30
  key_name             = "dev-ec2-2"
  instance_type        = each.value.instance_type
  az                   = each.value.az
  image_id             = "ami-06d365907eec04148"
  name                 = each.key

  profile_name = data.terraform_remote_state.iam.outputs.profile_name
  sg      = data.terraform_remote_state.network.outputs.sg_app
  subnets = data.terraform_remote_state.network.outputs.subnets_private
}
