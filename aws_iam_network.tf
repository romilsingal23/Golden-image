terraform {
  required_providers {

    toggles = {
      source  = "reinoudk/toggles"
      version = "0.3.0" // user-owned, hasn't been updated in a year... let's pin to this version
    }
  }
}

locals {
  image_assess_user_name = "${local.iam_name}_assess"
}

# IAM

resource "aws_iam_user" "image_assess" {
  name          = local.image_assess_user_name
  force_destroy = true

  tags = {
    Project = local.base_name
  }
}

resource "aws_iam_user_policy" "image_assess" {
  name = local.image_assess_user_name
  user = aws_iam_user.image_assess.name

  policy = data.aws_iam_policy_document.image_assess.json
}

resource "aws_iam_user_policy" "image_assess_for_azu_adoption_function" {
  count = local.deploy_azu_adoption_table ? 1 : 0
  name  = "${local.image_assess_user_name}_for_Adoption_Function"
  user  = aws_iam_user.image_assess.name

  policy = data.aws_iam_policy_document.image_assess_for_azu_adoption_function[0].json
}

data "aws_iam_policy_document" "image_assess" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:*Get*",
      "dynamodb:*Put*",
      "dynamodb:*Query*",
      "dynamodb:*Scan*",
      "dynamodb:*Update*",
    ]

    resources = [
      aws_dynamodb_table.common_image_table.arn
    ]
  }
  # Added to give Azure function access to publish to SNS to send mail to dev team about any vulnerabilities.
  # Used in gather function along with entry to DynamoDB.
  statement {
    effect = "Allow"

    actions = [
      "sns:Publish",
    ]

    resources = [
      "*",
    ]
  }
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      "*",
    ]
  }
}

data "aws_iam_policy_document" "image_assess_for_azu_adoption_function" {
  count = local.deploy_azu_adoption_table ? 1 : 0
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:*Get*",
      "dynamodb:*Put*",
      "dynamodb:*Query*",
      "dynamodb:*Scan*",
      "dynamodb:*Update*",
    ]

    resources = [
      aws_dynamodb_table.azu_adoption_data_table[0].arn,
      "${aws_dynamodb_table.common_image_table.arn}/index/*",
      "${aws_dynamodb_table.azu_adoption_data_table[0].arn}/index/*"
    ]
  }
}

resource "time_rotating" "rotate" {
  rotation_days = 60
}

resource "toggles_leapfrog" "toggle" {
  trigger = time_rotating.rotate.rotation_rfc3339
}

resource "aws_iam_access_key" "image_assess" {
  user   = aws_iam_user.image_assess.name
  status = "Active"
  lifecycle {
    replace_triggered_by = [
      toggles_leapfrog.toggle.alpha,
    ]

    create_before_destroy = true
  }
}

resource "aws_secretsmanager_secret" "iam_access_key" {
  name = "${local.namespaces_}iam_access_key"
}

resource "aws_secretsmanager_secret_version" "iam_access_key" {
  secret_id     = aws_secretsmanager_secret.iam_access_key.id
  secret_string = aws_iam_access_key.image_assess.id
}

resource "aws_secretsmanager_secret" "iam_secret_key" {
  name = "${local.namespaces_}iam_secret_key"
}

resource "aws_secretsmanager_secret_version" "iam_secret_key" {
  secret_id     = aws_secretsmanager_secret.iam_secret_key.id
  secret_string = aws_iam_access_key.image_assess.secret
}

# CLUTER TEST ROLES
resource "aws_iam_role" "node" {
  name               = "${local.namespace-}golden-test-cluster"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.cluster_service_trust.json
}

data "aws_iam_policy_document" "cluster_service_trust" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com","eks.amazonaws.com","elasticmapreduce.amazonaws.com","ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_instance_profile" "node" {
  name  = "${local.namespace-}golden-eks-node"
  role  = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.node.name
}

# Service role for EMR
resource "aws_iam_role" "emr_service_role" {
  name  = "${local.namespace_}emr_service_role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticmapreduce.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole" , "${aws_iam_policy.kms_use.arn}"]
}

data "aws_iam_policy_document" "kms_use" {
  statement {
    sid = "KMSUse"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:CreateGrant",
      "kms:GenerateDataKey*",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey",
    ]
    resources = [
      aws_kms_key.scan_notification.arn
    ]
  }
}


resource "aws_iam_policy" "kms_use" {
  name        = "${local.namespace_}KMS_Use"
  policy      = "${data.aws_iam_policy_document.kms_use.json}"
}

resource "aws_iam_role_policy_attachment" "build_kms" {
  role       = "${local.namespace_}golden_image_aws_build"
  policy_arn = "${aws_iam_policy.kms_use.arn}"
}


resource "aws_vpc" "build_network" {
  cidr_block           = "10.0.0.0/22"
  enable_dns_hostnames = "true"

  tags = tomap({ "Name" = "${local.build_name}" })
}

resource "aws_subnet" "build_network_public" {
  vpc_id                  = aws_vpc.build_network.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = sort(data.aws_availability_zones.available.names)[0]
  map_public_ip_on_launch = "true"

  tags = tomap({ "Name" = "${local.build_name}_ec2" })
}

resource "aws_subnet" "build_network_private" {
  vpc_id                  = aws_vpc.build_network.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = sort(data.aws_availability_zones.available.names)[0]
  map_public_ip_on_launch = "false"

  tags = tomap({ "Name" = "${local.build_name}_codebuild" })
}

resource "aws_subnet" "build_network_private_2" {
  vpc_id                  = aws_vpc.build_network.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = sort(data.aws_availability_zones.available.names)[1]
  map_public_ip_on_launch = "false"

  tags = tomap({ "Name" = "${local.build_name}_eks_test" })
}

resource "aws_internet_gateway" "outbound_internet" {
  vpc_id = aws_vpc.build_network.id

  tags = tomap({ "Name" = "${local.build_name}" })
}

resource "aws_eip" "outbound_internet" {
  vpc = true

  tags = tomap({ "Name" = "${local.build_name}" })
}

resource "aws_nat_gateway" "outbound_internet" {
  allocation_id = aws_eip.outbound_internet.id
  subnet_id     = aws_subnet.build_network_public.id
  depends_on    = [aws_internet_gateway.outbound_internet]

  tags = tomap({ "Name" = "${local.build_name}" })
}

resource "aws_route_table" "outbound_internet" {
  vpc_id = aws_vpc.build_network.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.outbound_internet.id
  }

  tags = tomap({ "Name" = "${local.build_name}_public" })
}

resource "aws_route_table_association" "outbound_internet" {
  subnet_id      = aws_subnet.build_network_public.id
  route_table_id = aws_route_table.outbound_internet.id
}

resource "aws_route_table" "codebuild_to_nat" {
  vpc_id = aws_vpc.build_network.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.outbound_internet.id
  }

  tags = tomap({ "Name" = "${local.build_name}_private" })
}

resource "aws_route_table_association" "codebuild_to_nat" {
  subnet_id      = aws_subnet.build_network_private.id
  route_table_id = aws_route_table.codebuild_to_nat.id
}

resource "aws_route_table_association" "codebuild_to_nat_2" {
  subnet_id      = aws_subnet.build_network_private_2.id
  route_table_id = aws_route_table.codebuild_to_nat.id
}

resource "aws_security_group" "build_instance_sg" {
  name   = "${local.build_name}_ec2"
  vpc_id = aws_vpc.build_network.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.codebuild_sg.id]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [
      "${aws_eip.outbound_internet.public_ip}/32",
      aws_vpc.build_network.cidr_block
    ]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = tomap({ "Name" = "${local.build_name}_ec2" })
}

resource "aws_security_group" "codebuild_sg" {
  name   = "${local.build_name}-codebuild"
  vpc_id = aws_vpc.build_network.id

  tags = tomap({ "Name" = "${local.build_name}_codebuild" })
}

# need these as a separate resource to avoid a cycle
resource "aws_security_group_rule" "codebuild_sg_egress_ec2" {
  type                     = "egress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.build_instance_sg.id
  security_group_id        = aws_security_group.codebuild_sg.id
}

resource "aws_security_group_rule" "codebuild_sg_egress_internet" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.codebuild_sg.id
}

# Create a separate service security group for EMR cluster tests
resource "aws_security_group" "master" {
  name                   = "${local.namespace-}emr-master-sg"
  vpc_id                 = aws_vpc.build_network.id
  revoke_rules_on_delete = true
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]

  }
}

resource "aws_security_group" "service_access" {
  name                   = "${local.namespace-}emr-service-sg"
  vpc_id                 = aws_vpc.build_network.id
  revoke_rules_on_delete = true
  ingress {
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.master.id]

  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]

  }
}
