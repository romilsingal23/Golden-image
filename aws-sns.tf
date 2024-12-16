
resource "aws_kms_key" "scan_notification" {
  description = "Encrypts the SNS Topic that forwards Inspector2 scan data to the AWS Golden Image API"
  policy      = local.is_local ? data.aws_iam_policy_document.scan_notification_kms.json : data.aws_iam_policy_document.scan_notification_kms_combined[0].json
}

resource "aws_kms_alias" "scan_notification" {
  name          = "alias/${local.namespace-}inspector2-events"
  target_key_id = aws_kms_key.scan_notification.arn
}

data "aws_iam_policy_document" "scan_notification_kms" {
  statement {
    sid = "Events"
    actions = [
      "kms:Decrypt",
      "kms:Decribe",
      "kms:Encrypt",
      "kms.ReEncrypt",
      "kms:GenerateDataKey*",
    ]
    principals {
      identifiers = ["events.amazonaws.com","elasticmapreduce.amazonaws.com"]
      type        = "Service"
    }
    resources = ["*"]
  }

  statement {
    sid = "notification access"
    actions = [
      "kms:Decrypt",
      "kms:Decribe",
      "kms:Encrypt",
      "kms.ReEncrypt",
      "kms:GenerateDataKey*",
    ]
    principals {
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${local.namespace_}build_notification_lambda/${local.namespace_}golden_images_send_build_notifications",
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${local.namespace_}golden_image_aws_archiver/${local.namespace_}golden_image_aws_archiver",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${local.namespaces_}golden_image_assess",
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${local.namespace_}golden_image_aws_cve_store/${local.namespace_}golden_image_aws_cve_store",
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${local.local_env}golden_image_aws_ec2_instance_delete/${local.local_env}golden_image_aws_ec2_instance_delete",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.namespace_}golden_image_aws_build"

      ]
      type        = "AWS"
    }
    resources = ["*"]
  }

  statement {
    sid = "SNS"
    actions = [
      "kms:Decrypt",
      "kms:Decribe",
      "kms:Encrypt",
      "kms.ReEncrypt",
      "kms:GenerateDataKey*",
    ]
    principals {
      identifiers = ["sns.amazonaws.com"]
      type        = "Service"
    }
    resources = ["*"]
  }

  statement {
    sid = "LPManage"
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"
      values   = local.key_owners
    }
    principals {
      identifiers = ["*"]
      type        = "AWS"
    }
    resources = ["*"]
  }

  statement {
    sid = "ReadandEncryptKey"
    actions = [
      "kms:Describe*",
      "kms:List*",
      "kms:Get*",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:CreateGrant",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    principals {
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
      type        = "AWS"
    }
    resources = ["*"]
  }
  depends_on = [aws_iam_user.image_assess]
}

data "aws_iam_policy_document" "scan_notification_kms_adoption" {
    count = local.is_local ? 0 : 1
    statement {
    sid = "notification access for adoption"
    actions = [
      "kms:Decrypt",
      "kms:Decribe",
      "kms:Encrypt",
      "kms.ReEncrypt",
      "kms:GenerateDataKey*",
    ]
    principals {
      identifiers = [
        "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${local.namespace_}golden_image_aws_adoption/${local.namespace_}golden_image_aws_adoption"
      ]
      type        = "AWS"
    }
    resources = ["*"]    
  }

}

data "aws_iam_policy_document" "scan_notification_kms_combined" {
  count = local.is_local ? 0 : 1
  source_policy_documents = [
    data.aws_iam_policy_document.scan_notification_kms.json,
    data.aws_iam_policy_document.scan_notification_kms_adoption[0].json
  ]
}

resource "aws_sns_topic" "scan_notification" {
  name              = "${local.namespace-}inspector-events"
  kms_master_key_id = aws_kms_key.scan_notification.arn

  provisioner "local-exec" {
    command = "sleep 10"
  }
}

resource "aws_sns_topic_policy" "scan_notification" {
  arn    = aws_sns_topic.scan_notification.arn
  policy = data.aws_iam_policy_document.scan_notification_sns.json
}

resource "aws_cloudwatch_event_rule" "scan_notification" {
  name          = "${local.namespace-}inspector2-scanning-events"
  description   = "Sends Inspector2 scan data from the SNS Topic to the AWS Golden Image API"
  event_pattern = <<EOF
{
  "source": ["aws.inspector2"]
}
EOF
}

resource "aws_cloudwatch_event_target" "scan_notification" {
  rule      = aws_cloudwatch_event_rule.scan_notification.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.scan_notification.arn
}


data "aws_iam_policy_document" "scan_notification_sns" {
  statement {
    sid    = "AllowEventsToPublish"
    effect = "Allow"
    actions = [
      "SNS:Publish"
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.scan_notification.arn]
  }
  statement {
    sid    = "__default_statement_ID"
    effect = "Allow"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:Receive"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_sns_topic.scan_notification.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
  }
}

resource "aws_sns_topic" "golden_images_notification_topic" {
  name              = "${local.namespace-}sns-notification-topic"
  kms_master_key_id = aws_kms_key.scan_notification.arn
  display_name = "Golden Images Notification"
  tags = {
    name = "${local.namespace-}sns-notification-topic-alert"
  }
}

resource "aws_sns_topic_subscription" "golden_images_notification_topic_subscription" {
  count     = length(local.emails_dev)
  topic_arn = aws_sns_topic.golden_images_notification_topic.arn
  protocol = "email"
  endpoint = local.emails_dev[count.index]
}

resource "aws_sns_topic_policy" "golden_images_notification_topic" {
  arn    = aws_sns_topic.golden_images_notification_topic.arn
  policy = data.aws_iam_policy_document.golden_images_codebuild_notification_topic_sns.json
}

data "aws_iam_policy_document" "golden_images_codebuild_notification_topic_sns" {
  statement {
    sid    = "AllowNotificationEventsToPublish"
    effect = "Allow"
    actions = [
      "SNS:Publish"
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.golden_images_notification_topic.arn]
  }
  statement {
    sid    = "__default_statement_ID"
    effect = "Allow"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
      "SNS:Receive"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_sns_topic.golden_images_notification_topic.arn]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
  }
}


resource "aws_cloudwatch_event_rule" "golden_images_codebuild_cloudwatch_event" {
  name          = "${local.namespace-}codebuild-cloudwatch-events"
  description   = "Sends email notification from the SNS Topic to subscriber when build failed"
  event_pattern = <<EOF
  {
    "source": ["aws.codebuild"],
    "detail-type": ["CodeBuild Build State Change"],
    "detail": {
      "project-name": [
          "${local.namespace_}golden_image_aws_build",
          "${local.namespace_}golden_image_azu_build"
      ],
      "build-status": ["STOPPED","FAILED"]
    }
  }
  EOF
}
