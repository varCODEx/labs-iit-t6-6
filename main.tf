terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-3"
}

resource "aws_vpc" "project_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

}

#data "aws_vpc" "project_vpc" {
#  default = true
#}

resource "aws_subnet" "project_subnet" {
  vpc_id     = aws_vpc.project_vpc.id
  cidr_block = "10.0.5.0/24"
}

resource "aws_security_group" "allow_ssh_to_ec2" {
  name        = "iit_allow_ssh_to_ec2"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.project_vpc.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "iit_ec2_sg"
  vpc_id = aws_vpc.project_vpc.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "iit_ec2_sg"
  }
}

resource "aws_instance" "tunnel_ec2" {
  ami           = "ami-0e1c5be2aa956338b"
  instance_type = "t2.micro"
  key_name      = "iit_terraform_keys"

  subnet_id              = aws_subnet.project_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  associate_public_ip_address = true

  tags = {
    Name = "tunnel_ec2"
  }
}

resource "aws_security_group" "ec2_to_elasticache" {
  name   = "iit_ec2_to_elasticache"
  vpc_id = aws_vpc.project_vpc.id

  ingress {
    from_port        = 11211
    to_port          = 11211
    protocol         = "tcp"
    security_groups  = [aws_security_group.ec2_sg.id]
    ipv6_cidr_blocks = []
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_27017_from_ec2"
  }
}

resource "aws_security_group" "ec2_to_docdb" {
  name   = "iit_ec2_to_docdb"
  vpc_id = aws_vpc.project_vpc.id

  ingress {
    from_port        = 27017
    to_port          = 27017
    protocol         = "tcp"
    security_groups  = [aws_security_group.ec2_sg.id]
    ipv6_cidr_blocks = []
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_11211_from_ec2"
  }
}

resource "aws_elasticache_subnet_group" "cache_subnet_group" {
  name       = "iit-cache-subnet-group"
  subnet_ids = [aws_subnet.project_subnet.id]
}

resource "aws_elasticache_cluster" "cache" {
  cluster_id           = "iit-cache"
  engine               = "memcached"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
  port                 = 11211
  security_group_ids   = [aws_security_group.ec2_to_elasticache.id]
  subnet_group_name    = aws_elasticache_subnet_group.cache_subnet_group.name
}

resource "aws_subnet" "project_subnet_2" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "eu-west-3a"
}

resource "aws_subnet" "project_subnet_3" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.0.7.0/24"
  availability_zone = "eu-west-3b"
}

resource "aws_docdb_subnet_group" "docdb_subnet_group" {
  name       = "iit-docdb-subnet-group"
  subnet_ids = [aws_subnet.project_subnet_2.id, aws_subnet.project_subnet_3.id]
}

resource "aws_docdb_cluster" "docdb" {
  cluster_identifier      = "iit-docdb-cluster"
  engine                  = "docdb"
  master_username         = "ddbadmin"
  master_password         = "zWKsBjsS2YJh!Zx"
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.ec2_to_docdb.id]
  db_subnet_group_name    = aws_docdb_subnet_group.docdb_subnet_group.name
}

output "docdb_endpoint" {
  value = aws_docdb_cluster.docdb.endpoint
}

output "elasticache_endpoint" {
  value = aws_elasticache_cluster.cache.configuration_endpoint
}

output "ec2_host" {
  value = aws_instance.tunnel_ec2.public_dns
}
