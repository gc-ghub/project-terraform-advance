terraform {
  backend "s3" {
    bucket = "tf-remote-backend-stark-industries"
    key    = "lab/terraform.tfstate"
    region = "ap-south-1"
  }

  required_version = "~>1.13.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.14.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

provider "aws" {
  alias  = "secondary"
  region = "ap-southeast-1"

}

provider "archive" {}
