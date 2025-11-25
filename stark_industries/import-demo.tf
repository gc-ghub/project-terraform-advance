#############################################
# DEMO — Terraform Import Example
#############################################

resource "aws_instance" "import_demo" {
  ami           = "ami-02b8269d5e85954ef"  # Ubuntu 22.04
  instance_type = "t3.micro"
   tags = {
    Name = "ec2_manual"
  }

  # We intentionally leave everything minimal
  # because Terraform will import attributes from AWS state.
}

output "imported_instance_id" {
  value = aws_instance.import_demo.id
}