data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../../function/handler.py"
  output_path = "${path.root}/.terraform/csv-sync.zip"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "ReadCsvObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]
  }

  statement {
    sid       = "SynchronizeRows"
    effect    = "Allow"
    actions   = ["dynamodb:Query", "dynamodb:BatchWriteItem"]
    resources = [var.table_arn]
  }

  statement {
    sid       = "WriteLambdaLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.table_name}-csv-sync"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.table_name}-csv-sync"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.table_name}-csv-sync"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 256
  depends_on       = [aws_iam_role_policy.lambda]

  environment {
    variables = {
      TABLE_NAME            = var.table_name
      SYNC_AWS_REGION       = var.aws_region
      S3_ENDPOINT_URL       = var.localstack ? var.lambda_localstack_endpoint : ""
      DYNAMODB_ENDPOINT_URL = var.localstack ? var.lambda_localstack_endpoint : ""
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.bucket_arn
}

resource "aws_s3_bucket_notification" "this" {
  bucket = var.bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.this.arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix       = var.csv_prefix
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
