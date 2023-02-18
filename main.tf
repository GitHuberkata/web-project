terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.53.0"
    }
  }
}



provider "aws" {
  region = "us-east-1"
}



# Create a VPC to launch our instances into
resource "aws_vpc" "vpc_web" {
  cidr_block = "10.0.0.0/16"
}



# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "inet_gate" {
  vpc_id = aws_vpc.vpc_web.id

  tags = {
        Name = "inet_gateway_codeweb"
    }
}



# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.vpc_web.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.inet_gate.id



}

# Create a subnet to launch our instances into
resource "aws_subnet" "pub_subnet" {
  vpc_id                  = aws_vpc.vpc_web.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
        Name = "public_subnet_petya"
    }
}



resource "aws_subnet" "private_subnet" {
    vpc_id =  aws_vpc.vpc_web.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-east-1a"
    tags = {
        Name = "private_subnet_petya"
    }
}



# NAT Gateway to allow private subnet to connect out the way
resource "aws_eip" "eip_nat_gateway" {
    vpc = true
}



resource "aws_nat_gateway" "nat_gateway" {
    allocation_id = aws_eip.eip_nat_gateway.id
    subnet_id     = "${aws_subnet.pub_subnet.id}"

    # To ensure proper ordering, add Internet Gateway as dependency
    depends_on = [aws_internet_gateway.inet_gate]

tags = {
    Name = "VPC - NATgateway"
    }

}



resource "aws_route_table" "private_route_table" {
    vpc_id = aws_vpc.vpc_web.id
    
    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = "${aws_nat_gateway.nat_gateway.id}" 
    }
    
    tags = {
        Name = "route_private"
    }
}
resource "aws_route_table" "pub_route_table" {
    vpc_id = "${aws_vpc.vpc_web.id}"
    
    route {
        cidr_block = "0.0.0.0/0" 
        gateway_id = "${aws_internet_gateway.inet_gate.id}" 
    }
    
    tags = {
        Name = "pub_route_table"
    }
}

resource "aws_route_table_association" "rta_private_subnet"{
    subnet_id = "${aws_subnet.private_subnet.id}"
    route_table_id = "${aws_route_table.private_route_table.id}"
}

resource "aws_route_table_association" "rta_public-subnet"{
    subnet_id = "${aws_subnet.pub_subnet.id}"
    route_table_id = "${aws_route_table.pub_route_table.id}"
}



# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "petya_securitygrp_elb"
  description = "Used in the terraform"
  vpc_id      = aws_vpc.vpc_web.id

  # Access from anywhere
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    // 78.83.117.100
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "custom1" {
  name        = "code-webserver"
  vpc_id      = aws_vpc.vpc_web.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    //78.83.117.100
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elb" "web" {
  name = "petya-elb"

  subnets         = ["${aws_subnet.pub_subnet.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${aws_instance.web.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
 
}

resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)

  instance_type = "t2.micro"
  ami           = "ami-0557a15b87f6559cf"
  
    # Personal SSH keypair.
  key_name      = "petya-aws-pem"




  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.custom1.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = aws_subnet.private_subnet.id

  # We run commands on instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
 
user_data = <<EOF
#!/bin/bash
sudo apt update
sudo apt install nginx -y
sudo service nginx start

EOF
 /*
  provisioner "remote-exec" {
    connection {
      host        = aws_eip.eip_nat_gateway.public_ip
      user        = "ubuntu"
      type        = "ssh"
      private_key = file("petya-aws-pem.pem")
    }
    inline = [
      "sudo apt update",
      "sudo apt install nginx -y",
      "sudo service nginx start"

    ]
  }

  */

  tags = {
        Name: "VM-to-test-NAT"
    }
}
#The output will give an address to be accessed from browser
output "address" {
  value = aws_elb.web.dns_name
}





