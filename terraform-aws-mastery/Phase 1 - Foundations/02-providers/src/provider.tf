# Default provider — used by all aws_* resources unless overridden
# No alias argument = this is the default instance
provider "aws" {
  region  = var.aws_region    # us-east-2
  profile = var.aws_profile   # default

  default_tags {
    tags = local.common_tags  # applied to every resource automatically
  }
}

# Aliased provider — used only by resources with provider = aws.west
# Same credentials, different region
provider "aws" {
  alias   = "west"            # referenced as aws.west in resources
  region  = "us-west-2"       # second region for compliance archive
  profile = var.aws_profile   # same credentials as default provider

  default_tags {
    tags = local.common_tags  # same tags applied in both regions
  }
}

# No provider "random" {} block needed — auto-instantiated from required_providers
