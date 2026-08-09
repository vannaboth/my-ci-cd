variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project_name" {
  type    = string
  default = "flask-app"
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "app_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_key_name" {
  type    = string
  default = "my-key"
}

variable "public_ip_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "docker_image" {
  type    = string
  default = "vannabothcd/flask-app"
}