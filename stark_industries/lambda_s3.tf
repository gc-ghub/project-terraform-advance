resource "aws_iam_role" "replica_lambda_role" {
  name = "${local.name_suffix}-replica-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replica_lambda_policy" {
  role = aws_iam_role.replica_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem"
        ],
        Resource = aws_dynamodb_table.s3_metadata.arn
      },
      {
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = aws_sns_topic.replica_notifications.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_lambda_function" "process_replica" {
  provider      = aws.secondary
  function_name = "${local.name_suffix}-replica-processor"
  handler       = "process_replica.lambda_handler"
  runtime       = "python3.10"
  role          = aws_iam_role.replica_lambda_role.arn

  filename = data.archive_file.replica_zip.output_path

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.s3_metadata.name
      SNS_TOPIC  = aws_sns_topic.replica_notifications.arn
    }
  }
}

data "archive_file" "replica_zip" {
  provider    = archive
  type        = "zip"
  source_file = "${path.module}/lambda/process_replica.py"
  output_path = "${path.module}/lambda/process_replica.zip"
}


resource "aws_s3_bucket_notification" "replica_events" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.replica_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_replica.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_replica_s3]
}

resource "aws_lambda_permission" "allow_replica_s3" {
  provider      = aws.secondary
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_replica.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.replica_bucket.arn
}
