###############################################
# S3 BUCKETS
###############################################

output "main_bucket" {
  description = "The name of the main S3 bucket"
  value       = aws_s3_bucket.main_bucket.bucket
}

output "logging_bucket" {
  description = "The name of the S3 logging bucket"
  value       = aws_s3_bucket.logging_bucket.bucket
}

output "replica_bucket" {
  description = "The replica bucket used for cross-region replication"
  value       = aws_s3_bucket.replica_bucket.bucket
}

###############################################
# EC2 OUTPUTS
###############################################

output "webserver_public_ips" {
  description = "The public IPs of the EC2 webservers"
  value       = [for instance in aws_instance.webserver : instance.public_ip]
}

output "webserver_ids" {
  description = "The instance IDs of the EC2 webservers"
  value       = [for instance in aws_instance.webserver : instance.id]
}

output "security_group_id" {
  description = "The ID of the web server security group"
  value       = aws_security_group.web_sg.id
}

output "ssh_commands" {
  description = "SSH commands for EC2 access"
  value = {
    for k, inst in aws_instance.webserver :
    k => "ssh -i ./${local.name_suffix}-key.pem ${lookup(local.ami_type_to_user, var.ami_type, "ec2-user")}@${inst.public_ip}"
  }
}

###############################################
# LAMBDA (METADATA)
###############################################

output "lambda_function_name" {
  description = "The name of the EC2 metadata Lambda function"
  value       = aws_lambda_function.get_metadata.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the EC2 metadata Lambda"
  value       = aws_lambda_function.get_metadata.arn
}

###############################################
# LAMBDA (REPLICA PROCESSOR)
###############################################

output "replica_lambda_name" {
  description = "Lambda that processes replicated objects"
  value       = aws_lambda_function.process_replica.function_name
}

output "replica_lambda_arn" {
  description = "ARN of the replica processor Lambda"
  value       = aws_lambda_function.process_replica.arn
}

###############################################
# API GATEWAY
###############################################

output "metadata_api_url" {
  description = "Execution ARN of metadata API"
  value       = "${aws_api_gateway_rest_api.metadata_api.execution_arn}/metadata"
}

output "api_invoke_url" {
  description = "Invoke URL for EC2 Metadata API"
  value       = "https://${aws_api_gateway_rest_api.metadata_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com/${aws_api_gateway_stage.metadata_stage.stage_name}/metadata"
}

output "upload_api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.presigner_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com/${aws_api_gateway_stage.presign_stage.stage_name}/presign"
  description = "Presign API invoke URL (POST)"
}


###############################################
# DYNAMODB + SNS
###############################################

output "dynamodb_table_name" {
  description = "DynamoDB table for replicated S3 objects"
  value       = aws_dynamodb_table.s3_metadata.name
}

output "sns_topic_arn" {
  description = "SNS topic used for replica notifications"
  value       = aws_sns_topic.replica_notifications.arn
}

###############################################
# IAM ROLES
###############################################

output "s3_replication_role_arn" {
  description = "IAM role used for cross-region replication"
  value       = aws_iam_role.s3_replication_role.arn
}

###############################################
# CLOUDWATCH LOGS
###############################################

output "metadata_lambda_log_group" {
  value = "/aws/lambda/${aws_lambda_function.get_metadata.function_name}"
}

output "replica_lambda_log_group" {
  value = "/aws/lambda/${aws_lambda_function.process_replica.function_name}"
}

output "presigner_lambda_log_group" {
  value = "/aws/lambda/${aws_lambda_function.presigner.function_name}"
}

################
# CLOUD FRONT
################
output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.domain_name
}


output "cloudfront_distribution_id" {
  description = "The ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.website.id
}


output "website_url" {
  description = "Full HTTPS URL of the Stark Industries Web Portal"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}
