data "aws_caller_identity" "current" {}

locals {
  function_name = "lets-encrypt"
  bucket_name   = var.bucket_name != "" ? var.bucket_name : format("%v-%v-%v", data.aws_caller_identity.current.account_id, local.function_name,"renew-certificates")
  sqs_name      = "${local.function_name}-renew-certificates-request"
  sqs_arn       = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sqs_name}"
  sqs_url       = "https://sqs.${var.aws_region}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${local.sqs_name}"
  sns_name      = "${local.function_name}-renew-certificates-result"
  sns_arn       = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.sns_name}"
  lambda_invoke_cerbot_name = "${local.function_name}-renew-certificates-invoke-cetbot"
  lambda_invoke_cerbot_arn    = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:lets-encrypt-renew-certificates-invoke-cetbot"
  lambda_find_expired_certificates_name = "${local.function_name}-renew-certificates-find-expired-certificates"
  lambda_find_expired_certificates_arn    = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:lets-encrypt-renew-certificates-find-expired-certificates"

}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name   = local.bucket_name
    Lambda = local.function_name
  }
}

data "aws_iam_policy_document" "sqs_policy" {
  policy_id = "${local.sqs_arn}/SQSDefaultPolicy"

  statement {
    sid    = "FromLambda"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "*"
      ]
    }

    actions = [
      "SQS:SendMessage",
    ]

    resources = [
      local.sqs_arn,
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"

      values = [
       local.lambda_find_expired_certificates_arn
      ]
    }
  }
}

resource "aws_sqs_queue" "this" {
  name                       = local.sqs_name
  visibility_timeout_seconds = var.function_timeout
  max_message_size           = 2048
  message_retention_seconds  = 86400
  policy                     = data.aws_iam_policy_document.sqs_policy.json

  tags = {
    Lambda = local.function_name
  }
}

data "aws_iam_policy_document" "find_expired_certificates" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = [aws_sqs_queue.this.arn]

    actions = [
      "sqs:SendMessage",
      "sqs:SendMessageBatch",
    ]
  }

  statement {
    sid    = "AllowACMPermissions"
    effect = "Allow"
    resources = [
      "*"
    ]
    actions = [
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate"
    ]
  }

  statement {
    sid       = "AllowSNSPermissions"
    effect    = "Allow"
    resources = [aws_sns_topic.this.arn]
    actions = [
      "sns:Publish"
    ]
  }

  statement {
    sid    = "AllowCloudwatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }

}


data "aws_iam_policy_document" "invoke_cerbot" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = [aws_sqs_queue.this.arn]

    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowSNSPermissions"
    effect    = "Allow"
    resources = [aws_sns_topic.this.arn]

    actions = [
      "sns:Publish"
    ]
  }

  statement {
    sid       = "AllowInvokingLambdas"
    effect    = "Allow"
    resources = ["arn:aws:lambda:${var.aws_region}:*:function:*"]
    actions   = ["lambda:InvokeFunction"]
  }

  statement {
    sid       = "AllowCreatingLogGroups"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
    actions   = ["logs:CreateLogGroup"]
  }

  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.function_name}*:*"]

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }

  statement {
    sid    = "AllowWritingS3"
    effect = "Allow"
    resources = [
      "${aws_s3_bucket.this.arn}",
      "${aws_s3_bucket.this.arn}/*"
    ]

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
  }

  statement {
    sid    = "AllowInvokeRoute53"
    effect = "Allow"
    resources = [
      "*"
    ]

    actions = [
      "route53:ListHostedZones",
      "route53:GetChange",
      "route53:ChangeResourceRecordSets"
    ]
  }

  statement {
    sid    = "AllowReadWriteCertificateManager"
    effect = "Allow"
    resources = [
      "*"
    ]
    actions = [
      "acm:AddTagsToCertificate",
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:ImportCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:UpdateCertificateOptions"
    ]
  }

  statement {
    sid    = "AllowCloudwatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*",
    ]
  }
}

resource "aws_iam_policy" "invoke_cerbot" {
  name   = "lambda-${local.function_name}-invoke-cerbot-policy"
  policy = data.aws_iam_policy_document.invoke_cerbot.json
}

resource "aws_iam_policy" "find_expired_certificates" {
  name   = "lambda-${local.function_name}-find-expired-certificates-policy"
  policy = data.aws_iam_policy_document.find_expired_certificates.json
}

resource "aws_iam_role" "invoke_cerbot" {
  name               = "lambda-${local.function_name}-invoke-cerbot-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  tags = {
    Lambda = local.function_name
  }
}

resource "aws_iam_role" "find_expired_certificates" {
  name               = "lambda-${local.function_name}-find-expired-certificates-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
  tags = {
    Lambda = local.function_name
  }
}

resource "aws_iam_role_policy_attachment" "invoke_cerbot" {
  policy_arn = aws_iam_policy.invoke_cerbot.arn
  role = aws_iam_role.invoke_cerbot.name
}

resource "aws_iam_role_policy_attachment" "find_expired_certificates" {
  policy_arn = aws_iam_policy.find_expired_certificates.arn
  role = aws_iam_role.find_expired_certificates.name
}

resource "aws_cloudwatch_log_group" "invoke_cerbot" {
  name              = "/aws/lambda/${local.lambda_invoke_cerbot_name}"
  retention_in_days = var.cloudwatch_log_retention
}

resource "aws_cloudwatch_log_group" "find_expired_certificates" {
  name              = "/aws/lambda/${local.lambda_find_expired_certificates_name}"
  retention_in_days = var.cloudwatch_log_retention
}

resource "aws_lambda_function" "invoke_cerbot" {
  function_name = local.lambda_invoke_cerbot_name
  memory_size = 128
  description = "Invoke Let’s Encrypt to refresh certificate"
  timeout = var.function_timeout
  runtime = "python3.6"
  filename = "${path.module}/lets-encrypt-renew-certificates.zip"
  handler = "invoke_cerbot_handler.lambda_handler"
  role = aws_iam_role.invoke_cerbot.arn

  environment {
    variables = {
      S3_BUCKET = local.bucket_name
      CERTBOT_SERVER_URL = var.certbot_server
      SNS_RESULT_ARN = aws_sns_topic.this.arn
    }
  }

  tags = {
    Lambda = local.function_name
  }

  depends_on    = ["aws_iam_role_policy_attachment.invoke_cerbot", "aws_cloudwatch_log_group.invoke_cerbot"]
}

resource "aws_lambda_function" "find_expired_certificates" {
  function_name = local.lambda_find_expired_certificates_name
  memory_size = 128
  description = "Find certificates to refresh by Let’s Encrypt"
  timeout = var.function_timeout
  runtime = "python3.6"
  filename = "${path.module}/lets-encrypt-renew-certificates.zip"
  handler = "find_expired_certificates_handler.lambda_handler"
  role = aws_iam_role.find_expired_certificates.arn

  environment {
    variables = {
      SNS_RESULT_ARN = aws_sns_topic.this.arn
      SQS_REQUEST_URL = local.sqs_url
      NB_DAYS_BEFORE_EXPIRATION = var.number_days_before_expiration
    }
  }

  tags = {
    Lambda = local.function_name
  }

  depends_on    = ["aws_iam_role_policy_attachment.find_expired_certificates", "aws_cloudwatch_log_group.find_expired_certificates"]
}

resource "aws_cloudwatch_event_rule" "every_x_minutes" {
  name = "every_x_minutes"
  description = "Fires every x minutes"
  schedule_expression = "rate(${var.scan_alarm_clock} minutes)"
}

resource "aws_cloudwatch_event_target" "check_every_x_minutes" {
  rule = "${aws_cloudwatch_event_rule.every_x_minutes.name}"
  target_id = "${local.function_name}_find_expired_certificates"
  arn = "${aws_lambda_function.find_expired_certificates.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_find_expired_certificates" {
  statement_id = "AllowExecutionFromCloudWatch"
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.find_expired_certificates.function_name}"
  principal = "events.amazonaws.com"
  source_arn = "${aws_cloudwatch_event_rule.every_x_minutes.arn}"
}

resource "aws_lambda_event_source_mapping" "this" {
  event_source_arn = aws_sqs_queue.this.arn
  function_name = aws_lambda_function.invoke_cerbot.arn
  enabled = true
}

resource "aws_sns_topic" "this" {
  name = local.sns_name
  tags = {
    Lambda = local.function_name
  }
}
