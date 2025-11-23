variable "project_name" {
  description = "The name of the project"
  type        = string
  default = "stark-industries"
}


variable "count_of_instances" {
  description = "Number of EC2 instances to launch"
  type        = number
  default = 2
}

variable "ami_type" {
  description = "Which AMI to use: ubuntu_2004, ubuntu_2204, amazon_linux2"
  type        = string
}

variable "instance_type" {
  description = "The instance type for the EC2 instance"
  type        = string
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address with the instance"
  type        = bool
}

variable "allowed_ports" {
  type        = list(number)
  description = "List of ports to allow inbound"
  default     = [22, 80]
}

variable "vpc_id" {
  description = "The VPC ID where resources will be created"
  type        = string

}


variable "api_stage_name" {
  description = "The name of the API Gateway stage"
  type        = string

}


variable "alert_email" {
  description = "Email address to receive SNS notifications for replicated S3 objects"
  type        = string
}
