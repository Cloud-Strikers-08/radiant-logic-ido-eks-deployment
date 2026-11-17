
# ============================================================
# 1. TERRAFORM AND PROVIDER
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# ============================================================
# 2. DATA SOURCES AND LOCALS
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  project_name = "radiant-ido"
  environment  = "lab"

  vpc_cidr = "10.0.0.0/16"

  azs = slice(
    data.aws_availability_zones.available.names,
    0,
    3
  )

  public_subnets = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  private_subnets = [
    "10.0.11.0/24",
    "10.0.12.0/24",
    "10.0.13.0/24"
  ]

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

# ============================================================
# 3. VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

# ============================================================
# 4. INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

# ============================================================
# 5. PUBLIC SUBNETS
# ============================================================

resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                    = "${local.project_name}-public-${count.index + 1}"
    Tier                                    = "Public"
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/radiant-ido-eks" = "shared"
  })
}

# ============================================================
# 6. PRIVATE SUBNETS
# ============================================================

resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name                                    = "${local.project_name}-private-${count.index + 1}"
    Tier                                    = "Private"
    "kubernetes.io/role/internal-elb"       = "1"
    "kubernetes.io/cluster/radiant-ido-eks" = "shared"
  })
}

# ============================================================
# 7. ELASTIC IP FOR NAT
# ============================================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.main]
}

# ============================================================
# 8. NAT GATEWAY
# ============================================================

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# ============================================================
# 9. PUBLIC ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# 10. PRIVATE ROUTE TABLE
# ============================================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ============================================================
# 11. EKS CLUSTER IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_cluster" {
  name = "${local.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "eks.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ============================================================
# 12. EKS WORKER NODE IAM ROLE
# ============================================================

resource "aws_iam_role" "eks_node" {
  name = "${local.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# ============================================================
# 13. EKS CLUSTER
# ============================================================

resource "aws_eks_cluster" "main" {
  name     = "${local.project_name}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.34"

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = aws_subnet.private[*].id

    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["35.154.36.95/32"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_route_table_association.private
  ]
}

# ============================================================
# 14. EKS MANAGED NODE GROUP
# ============================================================

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.project_name}-workers"

  node_role_arn = aws_iam_role.eks_node.arn

  subnet_ids = aws_subnet.private[*].id

  instance_types = ["m5.2xlarge"]
  capacity_type  = "ON_DEMAND"

  ami_type = "AL2023_x86_64_STANDARD"

  disk_size = 50

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload    = "radiant-ido"
    environment = "lab"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]
}

# ============================================================
# 15. EKS ADD-ONS
# ============================================================

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_pod_identity_association.ebs_csi
  ]
}

# ============================================================
# 16. S3 BUCKET
# ============================================================

resource "aws_s3_bucket" "ido" {
  bucket = "${local.project_name}-${data.aws_caller_identity.current.account_id}-ap-south-1"

  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-storage"
  })
}

# ============================================================
# 17. S3 ENCRYPTION
# ============================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "ido" {
  bucket = aws_s3_bucket.ido.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ============================================================
# 18. S3 VERSIONING
# ============================================================

resource "aws_s3_bucket_versioning" "ido" {
  bucket = aws_s3_bucket.ido.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================
# 19. S3 PUBLIC ACCESS BLOCK
# ============================================================

resource "aws_s3_bucket_public_access_block" "ido" {
  bucket = aws_s3_bucket.ido.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# 20. OUTPUTS
# ============================================================

output "vpc_id" {
  description = "Radiant Logic VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "s3_bucket_name" {
  description = "Radiant Logic storage bucket"
  value       = aws_s3_bucket.ido.bucket
}


# ============================================================
# EBS CSI DRIVER - DEDICATED POD IDENTITY IAM ROLE
# ============================================================

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.project_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

# ============================================================
# EKS POD IDENTITY AGENT
# ============================================================

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.4.1-eksbuild.3"

  depends_on = [
    aws_eks_node_group.main
  ]
}

# ============================================================
# EBS CSI - POD IDENTITY ASSOCIATION
# ============================================================

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.ebs_csi
  ]
}

# ============================================================
# EKS OIDC PROVIDER - IRSA FOUNDATION
# ============================================================

data "aws_eks_cluster" "oidc" {
  name = aws_eks_cluster.main.name
}

data "tls_certificate" "eks_oidc" {
  url = data.aws_eks_cluster.oidc.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.oidc.identity[0].oidc[0].issuer

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint
  ]

  tags = local.common_tags
}
