output "repository_urls" {
  value       = { for svc, repo in module.ecr : svc => repo.repository_url }
  description = "Map of service name to its ECR repository URL"
}
