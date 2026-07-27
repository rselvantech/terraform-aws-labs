data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "app" {
  name        = "cloudnova-app-sg"
  description = "CloudNova application security group"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  tags = {
    ManagedBy = "terraform-demo-10"
  }
}
