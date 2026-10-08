resource "aws_iam_role" "eks_cluster" {
  name = "cloudnova-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      # ↑ sts:TagSession added this session (VERIFY 1) — confirmed
      # required by AWS's own docs for Auto Mode cluster roles, and
      # specifically for tag propagation to AWS Load Balancer
      # resources created via this demo's own Ingress in Part D.
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── Auto Mode-specific policies on the CLUSTER's own role ────────────────
# Added this session: confirmed against AWS's own official documentation
# that these are attached alongside AmazonEKSClusterPolicy — they map
# onto Auto Mode's compute/storage/load-balancing/networking
# capabilities, which the base cluster policy alone doesn't cover.
resource "aws_iam_role_policy_attachment" "eks_cluster_auto_mode_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSComputePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy",
    "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy",
  ])
  role       = aws_iam_role.eks_cluster.name
  policy_arn = each.value
}

# ── Auto Mode's own node role — distinct from the cluster's role above ──
# Confirmed required per VERIFY 1: AWS's own API rejects a cluster with
# node_role_arn set but node_pools omitted (or vice versa) — the two
# arguments are conditionally coupled, not independently optional.
resource "aws_iam_role" "eks_auto_node" {
  name = "cloudnova-eks-auto-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # ↑ this role does NOT need sts:TagSession — confirmed against
      # AWS's own docs; that requirement is specific to the cluster
      # role above, not the node role.
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_auto_node_policy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
  role       = aws_iam_role.eks_auto_node.name
  policy_arn = each.value
}

resource "aws_eks_cluster" "main" {
  name     = "cloudnova-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.36" # [UNVERIFIED] the version AWS selected by default in the verification run — confirm against the current EKS version calendar before pinning

  # Required whenever Auto Mode is enabled — see VERIFY 1. Left at the
  # provider default (true), AWS rejects the create request outright.
  bootstrap_self_managed_addons = false

  vpc_config {
    subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  }

  compute_config {
    enabled       = true                           # Auto Mode
    node_pools    = ["general-purpose", "system"]  # confirmed required alongside node_role_arn — VERIFY 1
    node_role_arn = aws_iam_role.eks_auto_node.arn # confirmed required alongside node_pools — VERIFY 1
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true # required for built-in ALB support
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  access_config {
    authentication_mode = "API" # modern access-entry auth, not aws-auth ConfigMap
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_cluster_auto_mode_policies,
  ]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn # your own IAM identity
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  # ↑ referencing the access entry's own attribute — rather than
  # repeating data.aws_caller_identity.current.arn as a second literal
  # — creates a dependency edge so Terraform creates the entry first.
  # Confirmed necessary this session (VERIFY 1): without this
  # reference, the two resources have no dependency edge between them
  # and Terraform may create them in parallel, and the association can
  # fail with ResourceNotFoundException if it runs before the entry
  # finishes.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

data "aws_caller_identity" "current" {}
