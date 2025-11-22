###############################################
# WORKSPACE-AWARE LOCALS
###############################################

locals {
  # environment = current workspace
  env = terraform.workspace

  # used for naming all resources
  name_suffix = "${var.project_name}-${local.env}"

  # tags automatically adapt based on workspace
  required_tags = {
    Project     = var.project_name
    Environment = local.env
  }
}

###############################################
# AMI MAPPINGS
###############################################
locals {
  ami_map = {
    ubuntu_2004   = data.aws_ami.ubuntu_2004.id
    ubuntu_2204   = data.aws_ami.ubuntu_2204.id
    amazon_linux2 = data.aws_ami.amazon_linux2.id
  }
}

###############################################
# AVAILABILITY ZONE LOGIC
###############################################
locals {
  az_list = data.aws_availability_zones.available.names

  selected_azs = [
    for i in range(var.count_of_instances) :
    local.az_list[i % length(local.az_list)]
  ]
}

###############################################
# SSH USER BASED ON AMI TYPE
###############################################
locals {
  ami_type_to_user = {
    ubuntu_2004   = "ubuntu"
    ubuntu_2204   = "ubuntu"
    amazon_linux2 = "ec2-user"
  }
}
