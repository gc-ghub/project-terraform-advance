resource "aws_instance" "webserver" {
  for_each = {
    for idx, az in local.selected_azs :
    idx => az
  }

  ami                         = local.ami_map[var.ami_type]
  instance_type               = var.instance_type
  associate_public_ip_address = var.associate_public_ip_address
  availability_zone           = each.value
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  key_name                    = aws_key_pair.web_key.key_name
  user_data = templatefile("${path.module}/stark_industries_website.sh.tpl", {
    project_name     = var.project_name
    environment_name = local.env

    # EC2 metadata Lambda
    api_url = "https://${aws_api_gateway_rest_api.metadata_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com/${aws_api_gateway_stage.metadata_stage.stage_name}/metadata"

    # S3 presign API URL
    upload_api_url = "https://${aws_api_gateway_rest_api.upload_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com/${aws_api_gateway_stage.upload_stage.stage_name}/presign"
  })


  tags = merge(
    {
      Name = "${local.name_suffix}-webserver-${each.key + 1}"
      AZ   = each.value
    },
    local.required_tags
  )
}




resource "aws_security_group" "web_sg" {
  name        = "${local.name_suffix}-web-sg"
  description = "Allow SSH, HTTP, and HTTPS"
  vpc_id      = var.vpc_id

  # Dynamic ingress block
  dynamic "ingress" {
    for_each = var.allowed_ports
    content {
      description = "Allow port ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Egress block (Allow all outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.required_tags,
    {
      Name = "${local.name_suffix}-web-sg"
    }
  )
}


resource "aws_dynamodb_table" "s3_metadata" {
  provider = aws.secondary
  name     = "${local.name_suffix}-metadata"
  hash_key = "object_key"

  attribute {
    name = "object_key"
    type = "S"
  }

  billing_mode = "PAY_PER_REQUEST"
}


resource "aws_sns_topic" "replica_notifications" {
  provider = aws.secondary
  name     = "${local.name_suffix}-replica-events"
}

resource "aws_sns_topic_subscription" "email" {
  provider  = aws.secondary
  topic_arn = aws_sns_topic.replica_notifications.arn
  protocol  = "email"
  endpoint  = var.alert_email
}


