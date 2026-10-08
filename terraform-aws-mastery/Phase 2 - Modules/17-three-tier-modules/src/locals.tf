locals {
  tiers = {
    web = { port = 443,  cidr = "0.0.0.0/0" }
    app = { port = 8080, cidr = "10.0.0.0/16" }
    db  = { port = 5432, cidr = "10.0.0.0/16" }
  }
}
