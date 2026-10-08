module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 6.0"

  domain_name = "tf-mastery.rselvantech.com"
  zone_id     = data.aws_route53_zone.this.zone_id

  validation_method   = "DNS"
  wait_for_validation = true

  tags = {
    ManagedBy = "terraform-demo-20"
  }
}

resource "aws_route53_record" "placeholder" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "tf-mastery.rselvantech.com"
  type    = "CNAME"
  ttl     = 300
  records = ["rselvantech.com"]
}

