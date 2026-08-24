data "aws_iam_policy_document" "snowflake_assume_role" {
  statement {
    sid     = "SnowflakeStorageIntegrationTrust"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.snowflake_iam_user_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.snowflake_external_id]
    }
  }
}

resource "aws_iam_role" "snowflake_s3" {
  name               = var.role_name
  description        = "Allows the CareMatch Snowflake storage integration to read raw S3 data"
  assume_role_policy = data.aws_iam_policy_document.snowflake_assume_role.json
}

data "aws_iam_policy_document" "snowflake_s3_read" {
  statement {
    sid    = "ListCareMatchRawPrefix"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = ["arn:aws:s3:::${var.bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "raw",
        "raw/*",
      ]
    }
  }

  statement {
    sid    = "ReadCareMatchRawObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["arn:aws:s3:::${var.bucket_name}/raw/*"]
  }
}

resource "aws_iam_role_policy" "snowflake_s3_read" {
  name   = "carematch-raw-s3-read"
  role   = aws_iam_role.snowflake_s3.id
  policy = data.aws_iam_policy_document.snowflake_s3_read.json
}
