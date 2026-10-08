data "aws_route53_zone" "main" {
  name         = "rselvantech.com"
  private_zone = false
}

resource "aws_route53_record" "validation" {
  zone_id = data.aws_route53_zone.primary.zone_id   # Error
  name    = "_acme-challenge.app.rselvantech.com"
  type    = "CNAME"
  ttl     = 300
  records = ["dummy-validation-target.acm-validations.aws."]
}
