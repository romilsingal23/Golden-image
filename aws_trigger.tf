
resource "aws_s3_bucket" "builder" {
  bucket        = replace("${local.build_name}-${data.aws_caller_identity.current.account_id}", "_", "-")
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "builder" {
  bucket = aws_s3_bucket.builder.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "builder_bucket" {
  statement {
    sid     = "DenyInsecureCommunications"
    actions = ["s3:*"]
    effect  = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.builder.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "builder" {
  bucket = aws_s3_bucket.builder.id
  policy = data.aws_iam_policy_document.builder_bucket.json
}

resource "aws_iam_role" "builder" {
  name               = "${local.base_name}_codebuild"
  path               = "/golden-image-bakery/"
  assume_role_policy = data.aws_iam_policy_document.trust_policy_codebuild_svc.json
}

data "aws_iam_policy_document" "builder_role_1" {
  statement {
    sid = "AllowManageArtifacts"
    actions = [
      "s3:CreateBucket",
      "s3:GetObject",
      "s3:List*",
      "s3:PutObject",
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
    ]

    resources = [
      aws_s3_bucket.builder.arn,
      "${aws_s3_bucket.builder.arn}/*"
    ]
  }

  statement {
    sid = "AllowLogToCloudWatch"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "PublishAMIVersions"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
    ]

    resources = [
      aws_dynamodb_table.image_table.arn,
      aws_dynamodb_table.common_image_table.arn,
    ]
  }

  statement {
    sid    = "GetApiUrl"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      aws_secretsmanager_secret.image_api_url.arn,
    ]
  }

}

data "aws_iam_policy_document" "builder_role_2" {
  statement {
    sid = "AllowPackerAccess"
    actions = [
      "autoscaling:*",
      "ecs:*",
      "elasticmapreduce:*",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateKeypair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeImageAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "ec2:GetPasswordData",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
      "ssm:StartSession",
      "ssm:TerminateSession",
      "iam:PassRole",
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  statement {
    sid = "PackerInstanceProfileAccess"
    actions = [
      "iam:GetInstanceProfile"
    ]
    resources = [aws_iam_instance_profile.build_profile.arn]
  }

  statement {
    sid = "GoldenKMSAccess"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
      "kms:CreateGrant",
      "kms:Decrypt",
    ]
    resources = local.kms_arn_list
  }

  statement {
    sid = "UpdateAMITable"
    actions = [
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.image_table.arn,aws_dynamodb_table.common_image_table.arn]
  }

  statement {
    sid = "DeployEKSTestStackAccess"
    actions = [
      "iam:*",
      "eks:*",
      "ec2:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "SSMTestStackAccess"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:SendCommand",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "builder_role_1" {
  name   = "ExecutionPolicy1"
  role   = aws_iam_role.builder.id
  policy = data.aws_iam_policy_document.builder_role_1.json
}

resource "aws_iam_role_policy" "builder_role_2" {
  name   = "ExecutionPolicy2"
  role   = aws_iam_role.builder.id
  policy = data.aws_iam_policy_document.builder_role_2.json
}

resource "local_file" "buildspec" {
  content = jsonencode({
    version = "0.2"
    phases = {
      install = {
        commands = [
          "curl -qL -o packer.zip https://releases.hashicorp.com/packer/1.8.2/packer_1.8.2_linux_amd64.zip && unzip packer.zip",
          "./packer version",
          "curl -qL -o terraform.zip https://releases.hashicorp.com/terraform/1.2.3/terraform_1.2.3_linux_amd64.zip && unzip terraform.zip && mv terraform /usr/bin",
          "terraform version",
          "pip install loguru pywinrm pyyaml ansible==2.10 requests aws_requests_auth azure.identity azure.storage.blob",
          "ansible --version",
          "curl https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb -o session-manager-plugin.deb",
          "sudo dpkg -i session-manager-plugin.deb",
          "session-manager-plugin",
          ]
      }
      build = {
        commands = [
          "./execute_packer.sh"
        ]
      }
    }
  })
  filename = "${path.module}/codebuild/buildspec.yml"
}

data "archive_file" "ansible" {
  type        = "zip"
  source_dir  = "${path.module}/../../ansible"
  output_path = "${path.module}/codebuild/ansible.zip"
}

data "archive_file" "builder" {
  type        = "zip"
  source_dir  = "${path.module}/codebuild"
  output_path = "${path.root}/codebuild.zip"

  depends_on = [
    local_file.buildspec,
    data.archive_file.ansible
  ]
}

resource "aws_s3_object" "builder" {
  bucket                 = aws_s3_bucket.builder.bucket
  key                    = "${path.root}/codebuild.zip"
  source                 = data.archive_file.builder.output_path
  etag                   = data.archive_file.builder.output_md5
  server_side_encryption = "AES256"
}

resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/codebuild/${local.build_name}"
  retention_in_days = 30
}

resource "aws_secretsmanager_secret" "image_api_url" {
  name = "${local.namespace_}golden_image_api_url"
}

resource "aws_codebuild_project" "builder" {
  name          = local.build_name
  service_role  = aws_iam_role.builder.arn
  build_timeout = 180

  source {
    type     = "S3"
    location = "${aws_s3_bucket.builder.bucket}/codebuild.zip"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  vpc_config {
    vpc_id = aws_vpc.build_network.id

    subnets = [
      aws_subnet.build_network_private.id
    ]

    security_group_ids = [
      aws_security_group.codebuild_sg.id
    ]
  }

  environment {
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/standard:4.0"
    compute_type = "BUILD_GENERAL1_SMALL"

    environment_variable {
      name  = "namespace"
      value = var.namespace
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "namespacedash"
      value = local.namespace-
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "org_arns"
      value = jsonencode(local.shared_org_arn_list)
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ami_regions"
      value = jsonencode(local.ami_regions_list)
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "vpc_id"
      value = aws_vpc.build_network.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "subnet_id"
      value = aws_subnet.build_network_public.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "eks_subnet_1"
      value = aws_subnet.build_network_private.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "eks_subnet_2"
      value = aws_subnet.build_network_private_2.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ami_api_endpoint"
      value = aws_secretsmanager_secret.image_api_url.name
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "bucket_name"
      value = aws_s3_bucket.builder.bucket
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "kms_id"
      value = module.us_east_1.key_alias
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "kms_alias_map"
      value = local.kms_alias_map
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "security_group_id"
      value = aws_security_group.build_instance_sg.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "emr_service_security_group_id"
      value = aws_security_group.service_access.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "emr_master_security_group_id"
      value = aws_security_group.master.id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "emr_kms_key"
      value = aws_kms_key.scan_notification.arn
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "instance_profile"
      value = aws_iam_instance_profile.build_profile.name
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "image_table"
      value = aws_dynamodb_table.common_image_table.name
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_type"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "image_family"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_owner"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_name"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_arch"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_virtualization"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_mapping"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_device"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "os_root_volume"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "ssh_user"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "date_created"
      value = "WILL_BE_OVERWRITTEN"
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "client_secret"
      value = local.client_secret
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "tenant_id"
      value = local.tenant_id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "client_id"
      value = local.client_id
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "STORAGE_ACCOUNT_URL"
      value = local.storage_account_url_snow
      type  = "PLAINTEXT"
    }
    
  }
}
