resource "aws_ecs_cluster" "es-cluster" {
  name = "es-cluster"
}


data "template_file" "es" {
  template = file("${path.module}/templates/es.json")

  vars = {
    docker_image_url_es = var.docker_image_url_es
    region                  = var.region
  }
}

resource "aws_ecs_task_definition" "es" {
  family                = "es"
  container_definitions = data.template_file.es.rendered

  volume {
    name = "esdata"
    host_path = "/usr/share/elasticsearch/data"
  }

  volume {
    name = "esconfig"
    host_path = "/usr/share/elasticsearch/config/elasticsearch.yml"
  }

  requires_compatibilities = ["EC2"]
  cpu = "1024"
  memory = "1024"

  # role that the Amazon ECS container agent and the Docker daemon can assume
  execution_role_arn       = aws_iam_role.ec2_ecs_execution_role.arn

  # role that allows your Amazon ECS container task to make calls to other AWS services
  task_role_arn = aws_iam_role.ecs_task_role.arn
}

resource "aws_ecs_service" "es-cluster" {
  name                     = "es-cluster-service"
  cluster                  = aws_ecs_cluster.es-cluster.id
  task_definition          = aws_ecs_task_definition.es.arn
  desired_count            = 3

  #  (Optional) ARN of the IAM role that allows Amazon ECS to make calls to your load balancer on your behalf.
  #  This parameter is required if you are using a load balancer with your service,
  #   but only if your task definition does not use the awsvpc network mode.
  //  iam_role                 = aws_iam_role.ecs_service_role.arn

  placement_constraints {
    type       = "distinctInstance"
  }

  #  The task size allows you to specify a fixed size for your task.
  #  Task size is required for tasks using the Fargate launch type and is optional for the EC2 or External launch type.
  #  Container level memory settings are optional when task size is set.
  //  memory                   = "2048"
  //  cpu                      = "1024"
}