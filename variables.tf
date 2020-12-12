
//variable "aws_account_id" {
//  description = "AWS account ID"
//}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region."
  default     = "2"
}

variable "app_image" {
  description = "Docker image to run in the ECS cluster."
  // default     = "adongy/hostname-docker:latest"
}

variable "app_port" {
  description = "Port exposed by the docker image to redirect traffic to."
  default     = 3000
}

variable "app_count" {
  description = "Number of docker containers to run."
  default     = 2
}

variable "domain" {
  type        = string
  description = "The domain that this service resides within. Resources will also be tagged with this name."
}

variable "environment" {
  type        = string
  description = "The app environment. This will be used for tagging."
}

variable "fargate_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)."
  default     = "256"
}

variable "fargate_memory" {
  description = "Fargate instance memory to provision (in MiB)."
  default     = "512"
}

variable "region" {
  type        = string
  description = "The AWS region to deploy to."
}

variable "service" {
  type        = string
  description = "The service or application name. Resources will also be tagged with this name."
}