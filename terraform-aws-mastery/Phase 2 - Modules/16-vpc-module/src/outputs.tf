output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC created via the module"
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "IDs of the public subnets, one per AZ"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "IDs of the private subnets, one per AZ"
}
