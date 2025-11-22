resource "aws_iam_role" "lambda_role" {
  name = "${local.name_suffix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_suffix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ec2:DescribeInstances"],
        Resource = "*"
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






data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_ec2_metadata.py"
  output_path = "${path.module}/lambda/get_ec2_metadata.zip"
}

resource "aws_lambda_function" "get_metadata" {
  function_name = "${local.name_suffix}-ec2-metadata"

  runtime     = "python3.10"
  timeout     = 10
  memory_size = 256
  handler     = "get_ec2_metadata.lambda_handler"
  filename    = data.archive_file.lambda_zip.output_path
  role        = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      ENV_NAME     = local.env
    }
  }

  tags = merge(
    local.required_tags,
    {
      Name = "${local.name_suffix}-lambda"
    }
  )
}


resource "aws_api_gateway_rest_api" "metadata_api" {
  name = "${local.name_suffix}-metadata-api"
}

resource "aws_api_gateway_resource" "metadata_resource" {
  rest_api_id = aws_api_gateway_rest_api.metadata_api.id
  parent_id   = aws_api_gateway_rest_api.metadata_api.root_resource_id
  path_part   = "metadata"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.metadata_api.id
  resource_id   = aws_api_gateway_resource.metadata_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.metadata_api.id
  resource_id = aws_api_gateway_resource.metadata_resource.id
  http_method = aws_api_gateway_method.get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_metadata.invoke_arn
}

/*
resource "aws_api_gateway_method_response" "cors_method_response" {
  rest_api_id = aws_api_gateway_rest_api.metadata_api.id
  resource_id = aws_api_gateway_resource.metadata_resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}


resource "aws_api_gateway_integration_response" "cors_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.metadata_api.id
  resource_id = aws_api_gateway_resource.metadata_resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }
}

*/


resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_metadata.function_name
  principal     = "apigateway.amazonaws.com"
}


resource "aws_api_gateway_deployment" "metadata_deployment" {
  rest_api_id = aws_api_gateway_rest_api.metadata_api.id

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_api_gateway_stage" "metadata_stage" {
  rest_api_id   = aws_api_gateway_rest_api.metadata_api.id
  deployment_id = aws_api_gateway_deployment.metadata_deployment.id
  stage_name    = var.api_stage_name
}

