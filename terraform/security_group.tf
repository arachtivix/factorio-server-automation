# Security Group for Factorio Server
resource "aws_security_group" "factorio_server" {
  name        = "factorio-server-sg"
  description = "Security group for Factorio server"
  vpc_id      = var.vpc_id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr_blocks]
  }

  # Factorio game port (UDP)
  ingress {
    description = "Factorio game port"
    from_port   = 34197
    to_port     = 34197
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Factorio RCON port (TCP) - for admin access
  ingress {
    description = "Factorio RCON port"
    from_port   = 27015
    to_port     = 27015
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr_blocks]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Factorio Server Security Group"
    Application = "Factorio"
  }
}
