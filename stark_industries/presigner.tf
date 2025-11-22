###############################################
# presigner.tf  — Presign API (Lambda + API Gateway)
#
# Notes:
# - This file assumes `archive` provider is configured in root (for data.archive_file).
# - Ensure aws_s3_bucket.main_bucket exists in same module.
# - We use an OPTIONS mock integration to satisfy CORS preflight.
# - Integration to Lambda uses AWS_PROXY (Lambda proxy integration).
###############################################

###############################################
#  PRESIGNER LAMBDA ZIP (archive provider)
###############################################
data "archive_file" "presigner_zip" {
  provider    = archive
  type        = "zip"
  source_file = "${path.module}/lambda/presigner.py"
  output_path = "${path.module}/lambda/presigner.zip"
}

###############################################
#  IAM ROLE FOR PRESIGNER LAMBDA
###############################################
resource "aws_iam_role" "presigner_role" {
  name = "${local.name_suffix}-presigner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
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
          "s3:PutObjectAcl",
          "s3:ListBucket"
        ],
        # permit access to the main bucket and its objects
        Resource = [
          aws_s3_bucket.main_bucket.arn,
          "${aws_s3_bucket.main_bucket.arn}/*"
        ]
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
#  PRESIGNER LAMBDA FUNCTION
###############################################
resource "aws_lambda_function" "presigner" {
  function_name = "${local.name_suffix}-presigner"
  runtime       = "python3.10"
  handler       = "presigner.lambda_handler"
  filename      = data.archive_file.presigner_zip.output_path
  role          = aws_iam_role.presigner_role.arn
  timeout       = 10
  memory_size   = 128

  # Only set non-reserved environment keys (avoid AWS_REGION etc.)
  environment {
    variables = {
      BUCKET          = aws_s3_bucket.main_bucket.bucket
      PRESIGN_EXPIRES = "300"
    }
  }

  tags = merge(local.required_tags, { Name = "${local.name_suffix}-presigner" })
}

###############################################
#  REST API — upload_api (/presign)
###############################################
resource "aws_api_gateway_rest_api" "upload_api" {
  name        = "${local.name_suffix}-upload-api"
  description = "API for presigned upload URLs"
}

resource "aws_api_gateway_resource" "upload_resource" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  parent_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  path_part   = "presign"
}

###############################################
#  OPTIONS method — Mock integration to satisfy CORS preflight
#  This avoids OPTIONS being forwarded to Lambda and lets the browser preflight succeed.
###############################################
resource "aws_api_gateway_method" "upload_options" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.upload_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method

  # Mock integration returns a 200 for OPTIONS with CORS headers
  type = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

# Return CORS headers for the mock integration
resource "aws_api_gateway_method_response" "options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.options_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
  }

  response_templates = {
    "application/json" = ""
  }
}

###############################################
#  ANY method for /presign -> Lambda proxy integration
#  Using ANY ensures POST, etc. are covered. We use proxy (AWS_PROXY).
###############################################
resource "aws_api_gateway_method" "upload_any_method" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  resource_id   = aws_api_gateway_resource.upload_resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_any_integration" {
  rest_api_id             = aws_api_gateway_rest_api.upload_api.id
  resource_id             = aws_api_gateway_resource.upload_resource.id
  http_method             = aws_api_gateway_method.upload_any_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.presigner.invoke_arn
}

###############################################
#  method response for proxyed methods — add headers so API Gateway will include them in responses
#  (Only necessary for non-proxy integrations; proxy integration returns headers from Lambda)
###############################################
resource "aws_api_gateway_method_response" "upload_method_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_any_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response for the ANY method — for proxy integration AWS will use Lambda response directly.
# We do not add an integration_response for every status code here because AWS_PROXY forwards Lambda responses.

###############################################
#  DEPLOYMENT & STAGE
#  Use triggers with relevant IDs so terraform will re-deploy when methods/integrations change.
###############################################
resource "aws_api_gateway_deployment" "upload_deployment" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id

  # Use a stable hash of important resource IDs — ensures a new deployment when methods/integrations change.
  triggers = {
    redeploy = sha1(join(",", [
      aws_api_gateway_method.upload_any_method.id,
      aws_api_gateway_integration.upload_any_integration.id,
      aws_api_gateway_method.upload_options.id,
      aws_api_gateway_integration.options_integration.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.upload_any_integration,
    aws_api_gateway_integration.options_integration
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "upload_stage" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  deployment_id = aws_api_gateway_deployment.upload_deployment.id
  stage_name    = "dev"
}

###############################################
#  GATEWAY RESPONSES (improve messages for missing token / 4xx)
###############################################
resource "aws_api_gateway_gateway_response" "missing_auth" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  response_type = "MISSING_AUTHENTICATION_TOKEN"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
  }

  response_templates = {
    "application/json" = "{\"message\":\"invalid path or method\"}"
  }
}

resource "aws_api_gateway_gateway_response" "default_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
  }
}

###############################################
#  ALLOW API GATEWAY TO CALL LAMBDA
###############################################
resource "aws_lambda_permission" "allow_api_invoke_presigner" {
  statement_id  = "AllowExecFromAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigner.function_name
  principal     = "apigateway.amazonaws.com"

  # Allow any stage/method of this API to invoke the Lambda
  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.upload_api.id}/*/*"
}
