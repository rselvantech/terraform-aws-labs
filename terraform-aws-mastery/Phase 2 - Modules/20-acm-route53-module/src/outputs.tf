# output "certificate_arn" {
#   value       = module.acm.certificate_arn
#   description = "ARN of the validated ACM certificate"
# }

output "certificate_arn" {
  value = module.acm.acm_certificate_arn
}

output "zone_id" {
  value       = data.aws_route53_zone.this.zone_id
  description = "The real rselvantech.com hosted zone ID"
}
