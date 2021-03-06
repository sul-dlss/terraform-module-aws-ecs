/*====
IAM task role
======*/
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.service_name}-ecs-task-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags {
    terraform = "true"
    project   = "${var.project}"
  }
}

/*====
ECS task definitions
======*/
resource "aws_ecs_task_definition" "service" {
  family                   = "${var.service_name}"
  container_definitions    = "${var.container_definition}"
  requires_compatibilities = ["${var.service_type}"]
  network_mode             = "awsvpc"
  task_role_arn            = "${aws_iam_role.ecs_task_role.arn}"
  execution_role_arn       = "${var.execution_role_arn}"
  cpu                      = "${var.cpu}"
  memory                   = "${var.memory}"

  lifecycle {
    create_before_destroy = true
  }

  tags {
    terraform = "true"
    project   = "${var.project}"
  }
}

/*====
Security Group
======*/
locals {
  alb_sg = "${var.alb_sg != "" ? var.alb_sg : data.aws_security_group.cluster_alb_sg.id}"
}

resource "aws_security_group" "ecs_service" {
  vpc_id      = "${var.vpc_id}"
  name        = "${var.service_name}-ecs-service-sg"
  description = "Allow egress from container"

  tags {
    Name      = "${var.service_name}-ecs-service-sg"
    terraform = "true"
    project   = "${var.project}"
  }
}

resource "aws_security_group_rule" "service_egress" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.ecs_service.id}"
}

resource "aws_security_group_rule" "service_ingress" {
  type                     = "ingress"
  from_port                = "${var.port}"
  to_port                  = "${var.port}"
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.ecs_service.id}"
  source_security_group_id = "${local.alb_sg}"
}

resource "aws_ecs_service" "service" {
  name            = "${var.service_name}"
  task_definition = "${aws_ecs_task_definition.service.arn}"
  desired_count   = "${var.min_capacity}"
  launch_type     = "${var.service_type}"
  cluster         = "${data.aws_ecs_cluster.cluster.id}"

  network_configuration {
    security_groups = ["${aws_security_group.ecs_service.id}"]
    subnets         = ["${split(",", var.private_subnets)}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.service.arn}"
    container_name   = "${var.service_name}"
    container_port   = "${var.port}"
  }

  # comment this block out if you want to restart the service with changes
  # to the local container_definitions for this service.
  lifecycle {
    ignore_changes = ["desired_count"]
  }

  depends_on = ["aws_alb_target_group.service", "aws_alb_listener_rule.service_http", "aws_alb_listener_rule.service_https", "aws_ecs_task_definition.service"]

#  FIXME: AWS changed the ARN format.  We've opted in but there are still
#  problems with using the old formats, which mean we can't tag.
#  tags {
#    terraform = "true"
#    project   = "${var.project}"
#  }
}
