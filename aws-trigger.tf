
data "aws_iam_policy_document" "build_trigger" {
  statement {
    sid    = "AllowLogging"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

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
      aws_s3_bucket.supported_images.arn,
      "${aws_s3_bucket.supported_images.arn}/*",
    ]
  }

  statement {
    sid    = "ReadCurrentAMIs"
    effect = "Allow"

    actions = [
      "ec2:DescribeImages",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "TriggerCodeBuild"
    effect = "Allow"

    actions = [
      "codebuild:StartBuild",
    ]

    resources = [
      aws_codebuild_project.builder.arn,
    ]
  }
}

resource "aws_iam_role" "build_trigger" {
  name               = "${local.build_name}_trigger"
  assume_role_policy = data.aws_iam_policy_document.trust_policy_lambda_svc.json
}

resource "aws_iam_role_policy" "build_trigger" {
  name   = "LambdaExecutionPolicy"
  role   = aws_iam_role.build_trigger.name
  policy = data.aws_iam_policy_document.build_trigger.json
}

resource "aws_cloudwatch_log_group" "build_trigger" {
  name              = "/aws/lambda/${local.build_name}_trigger"
  retention_in_days = 30
}

data "archive_file" "build_trigger" {
  type        = "zip"
  source_file = "${path.module}/../../python/aws_build/build_trigger/main.py"
  output_path = "${path.root}/build_trigger.zip"
}

resource "aws_lambda_function" "build_trigger" {
  filename      = data.archive_file.build_trigger.output_path
  function_name = "${local.build_name}_trigger"
  role          = aws_iam_role.build_trigger.arn
  handler       = "main.lambda_handler"
  timeout       = 180
  memory_size   = 256

  source_code_hash = data.archive_file.build_trigger.output_base64sha256

  runtime = "python3.9"

  environment {
    variables = {
      project_name = aws_codebuild_project.builder.name
      supported_images_bucket = "${local.namespaces-}supported-images"
    }
  }
}

resource "aws_s3_bucket" "supported_images" {
  bucket        = "${local.namespaces-}supported-images"
  force_destroy = true
}

resource "aws_s3_object" "supported_images" {
  bucket                 = aws_s3_bucket.supported_images.bucket
  key                    = "supported_images.json"
  source                 = "${path.module}/../../supported_images.json"
  etag                   = filemd5("${path.module}/../../supported_images.json")
  server_side_encryption = "AES256"
}

resource "aws_cloudwatch_event_rule" "build_trigger" {
  name        = "${local.build_name}_trigger"
  description = "Nightly trigger for building AWS Golden Images"

  schedule_expression = "cron(0 5 * * ? *)" # AMIs built at 5 UTC, which is midnight CST
}

resource "aws_cloudwatch_event_target" "build_trigger" {
  rule      = aws_cloudwatch_event_rule.build_trigger.name
  target_id = local.build_name
  arn       = aws_lambda_function.build_trigger.arn
}

resource "aws_lambda_permission" "build_trigger" {
  count = local.is_local ? 0 : 1
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.build_trigger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.build_trigger.arn
}
