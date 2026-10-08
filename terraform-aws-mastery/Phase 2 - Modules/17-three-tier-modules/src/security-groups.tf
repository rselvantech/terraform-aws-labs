module "tier_sg" {
  for_each = local.tiers

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "cloudnova-${each.key}-tier-sg"
  description = "Security group for the ${each.key} tier"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    tier_access = {
      from_port   = each.value.port
      to_port     = each.value.port
      ip_protocol = "tcp"
      cidr_ipv4   = each.value.cidr
      description = "${each.key} tier access"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  }

  tags = {
    ManagedBy = "terraform-demo-17"
    Tier      = each.key
  }
}
