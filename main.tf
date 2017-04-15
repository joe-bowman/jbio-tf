# Specify the provider and access details
provider "aws" {
  region                  = "eu-west-2"
  shared_credentials_file = "/Users/joebowman/.aws/credentials"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.main.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# A security group for the ELB so it is accessible via the web
#resource "aws_security_group" "elb" {
#  name        = "terraform_example_elb"
#  description = "Used in the terraform"
#  vpc_id      = "${aws_vpc.main.id}"

  # HTTP access from anywhere
#  ingress {
#    from_port   = 80
#    to_port     = 80
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }

  # outbound internet access
#  egress {
#    from_port   = 0
#    to_port     = 0
#    protocol    = "-1"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.main.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#resource "aws_elb" "web" {
#  name = "terraform-example-elb"
#
#  subnets         = ["${aws_subnet.default.id}"]
#  security_groups = ["${aws_security_group.elb.id}"]
#  instances       = ["${aws_instance.web.id}"]
#
#  listener {
#    instance_port     = 80
#    instance_protocol = "http"
#    lb_port           = 80
#    lb_protocol       = "http"
#  }
#}

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

resource "aws_instance" "web" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"
    private_key = "${file("/Users/joebowman/joebowman.io/keys/aws")}"
    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # private_ip = "10.0.1.3"
  # private_dns = "web01"

  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.auth.id}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.default.id}"

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost web-01/' /etc/hosts",
      "echo 'web-01' | sudo tee /etc/hostname",
      "sudo hostname web-01",
      "sudo apt-get install -y git",
      "curl -L https://bootstrap.saltstack.com -o bootstrap_salt.sh",
      "sudo sh bootstrap_salt.sh",
      "ssh-keyscan -H github.com | sudo tee /root/.ssh/known_hosts",
      "sudo git clone https://github.com/joe-bowman/jbio-salt /srv/saltstack",
      "sudo cp /srv/saltstack/salt/minion /etc/salt/minion",
      "sudo apt-get install -y python-pygit2",
      "sudo service salt-minion stop",
      "sudo salt-call state.highstate"
    ]
  }
}
