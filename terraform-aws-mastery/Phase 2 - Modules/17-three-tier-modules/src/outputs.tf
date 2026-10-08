output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC"
}

output "web_tier_sg_id" {
  value       = module.tier_sg["web"].id
  description = "Security group ID for the web tier specifically"
}

output "tier_security_group_ids" {
  value       = { for tier, sg in module.tier_sg : tier => sg.id }
  description = "Map of every tier name to its security group ID"
}
