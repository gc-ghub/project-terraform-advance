###############################################
# PRESIGNER LAMBDA ZIP
###############################################
data "archive_file" "presigner_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/presigner.py"
  output_path = "${path.module}/lambda/presigner.zip"
}

###############################################
# IAM ROLE FOR PRESIGNER LAMBDA
###############################################
resource "aws_iam_role" "presigner_role" {
  name = "${local.name_suffix}-presigner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "presigner_policy" {
  name = "${local.name_suffix}-presigner-policy"
  role = aws_iam_role.presigner_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ],
        Resource = "${aws_s3_bucket.main_bucket.arn}/*"
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

###############################################
# PRESIGNER LAMBDA FUNCTION
###############################################
resource "aws_lambda_function" "presigner" {
  function_name = "${local.name_suffix}-presigner"
  handler       = "presigner.lambda_handler"
  runtime       = "python3.10"
  filename      = data.archive_file.presigner_zip.output_path
  role          = aws_iam_role.presigner_role.arn
  timeout       = 10

  environment {
    variables = {
      BUCKET          = aws_s3_bucket.main_bucket.bucket
      PRESIGN_EXPIRES = "300"
    }
  }
}

###############################################
# API GATEWAY REST API
###############################################
resource "aws_api_gateway_rest_api" "presigner_api" {
  name = "${local.name_suffix}-presigner-api"
}

resource "aws_api_gateway_resource" "presign_resource" {
  rest_api_id = aws_api_gateway_rest_api.presigner_api.id
  parent_id   = aws_api_gateway_rest_api.presigner_api.root_resource_id
  path_part   = "presign"
}

###############################################
# POST METHOD → AWS_PROXY → Lambda
###############################################
resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.presigner_api.id
  resource_id   = aws_api_gateway_resource.presign_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.presigner_api.id
  resource_id = aws_api_gateway_resource.presign_resource.id
  http_method = aws_api_gateway_method.post_method.http_method

  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.presigner.invoke_arn
}

###############################################
# OPTIONS METHOD — MOCK integration (CORS)
# IMPORTANT: MOCK ensures OPTIONS never invokes Lambda
###############################################
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.presigner_api.id
  resource_id   = aws_api_gateway_resource.presign_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.presigner_api.id
  resource_id = aws_api_gateway_resource.presign_resource.id
  http_method = "OPTIONS"

  type = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}



resource "aws_api_gateway_method_response" "options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.presigner_api.id
  resource_id = aws_api_gateway_resource.presign_resource.id
  http_method = "OPTIONS"
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}


resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.presigner_api.id
  resource_id = aws_api_gateway_resource.presign_resource.id
  http_method = "OPTIONS"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_method_response.options_method_response
  ]
}



###############################################
# DEPLOYMENT + STAGE
# We include depends_on to ensure methods/integrations exist when creating deployment
###############################################
resource "aws_api_gateway_deployment" "presign_deployment" {
  rest_api_id = aws_api_gateway_rest_api.presigner_api.id

  # Force new deployment when code/infra changes that affect API
  triggers = {
    lambda_version = aws_lambda_function.presigner.source_code_hash != null ? aws_lambda_function.presigner.source_code_hash : timestamp()
  }

  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.options_integration,
    aws_api_gateway_integration_response.options_integration_response
  ]
}

resource "aws_api_gateway_stage" "presign_stage" {
  deployment_id = aws_api_gateway_deployment.presign_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.presigner_api.id
  stage_name    = "dev"
}

###############################################
# LAMBDA PERMISSION → API GATEWAY (POST)
###############################################
resource "aws_lambda_permission" "presigner_allow_api" {
  statement_id  = "AllowAPIGatewayInvokePresigner"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigner.function_name
  principal     = "apigateway.amazonaws.com"
  # Allow invocation from this API + any stage/method
  source_arn    = "${aws_api_gateway_rest_api.presigner_api.execution_arn}/*/*"
}



