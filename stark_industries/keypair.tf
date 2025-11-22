resource "tls_private_key" "web_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "web_key" {
  key_name   = "${local.name_suffix}-key"
  public_key = tls_private_key.web_key.public_key_openssh
}

# Save private key locally after apply
resource "local_file" "private_key" {
  content  = tls_private_key.web_key.private_key_pem
  filename = "${path.module}/${local.name_suffix}-key.pem"
}
