data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name                  = "carematch-${var.environment}-airflow"
  airflow_password_path = "/carematch/${var.environment}/airflow/admin_password"
}

resource "aws_vpc" "airflow" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "airflow" {
  vpc_id = aws_vpc.airflow.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.airflow.id
  cidr_block              = "10.42.10.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.airflow.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.airflow.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.airflow.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = { Name = "${local.name}-s3" }
}

resource "aws_security_group" "airflow" {
  name        = local.name
  description = "No inbound access; administer Airflow through SSM Session Manager"
  vpc_id      = aws_vpc.airflow.id

  egress {
    description = "HTTPS and package/image downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = local.name }
}

resource "aws_iam_role" "airflow" {
  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.airflow.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "airflow_data" {
  name = "carematch-s3-and-bootstrap"
  role = aws_iam_role.airflow.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InspectLandingBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}"
      },
      {
        Sid    = "WritePipelineObjects"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetObject",
          "s3:ListMultipartUploadParts",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}/raw/*",
          "arn:aws:s3:::${var.s3_bucket_name}/manifests/*",
          "arn:aws:s3:::${var.s3_bucket_name}/airflow-logs/*"
        ]
      },
      {
        Sid      = "StoreGeneratedAdminPassword"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.airflow_password_path}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "airflow" {
  name = local.name
  role = aws_iam_role.airflow.name
}

resource "aws_instance" "airflow" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.airflow.id]
  iam_instance_profile        = aws_iam_instance_profile.airflow.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_gib
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region      = var.aws_region
    bucket_name     = var.s3_bucket_name
    password_path   = local.airflow_password_path
    repository_url  = var.repository_url
    repository_ref  = var.repository_ref
    compose_version = "v2.40.3"
    buildx_version  = "v0.20.1"
  })

  depends_on = [
    aws_iam_role_policy.airflow_data,
    aws_iam_role_policy_attachment.ssm_core,
    aws_route_table_association.public,
  ]

  tags = { Name = local.name }
}
