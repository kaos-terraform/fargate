# About

This module will set up networking and security for a Docker container to run on AWS Fargate.

It will:

- Set up an application load balancer.
- Set up an ECS cluster, an ECS task, and networking to connect to the container.
- Set up the VPC, subnets, and gateways.
- Define appropriate security groups.

# Usage

Add this to your terraform file.

```tf
module "fargate_container" {
  source = "github.com/kaos-terraform/fargate"

  az_count = 2
  app_image = "foo/image-name:latest"
  app_port = 3000
  app_count = 2
  domain = "my-domain"
  environment = "test"
  fargate_cpu = 256
  fargate_memory = 512
  region = "us-west-1"
  service = "my-service"
}

# output the URL to access the server
output "base_url" {
  value = module.fargate_container.base_url
}
```

## Variables

| Variable | Type | Default | Description | 
| -------- | ---- | ------- | ----------- |
| az_count| number | 2 | Number of AZs to cover in a given AWS region. |
| app_image | string | | Docker image to run in the ECS cluster. |
| app_port | string | 3000 | Port exposed by the docker image to redirect traffic to. |
| app_count | number | 2 | Number of docker containers to run. |
| domain | string | | The domain that this service resides within. Resources will also be tagged with this name. |
| environment | string | | The app environment. This will be used for tagging. |
| fargate_cpu | string | 256 | Fargate instance CPU units to provision (1 vCPU = 1024 CPU units). |
| fargate_memory | string | 512 | Fargate instance memory to provision (in MiB). |
| region | string | | The AWS region to deploy to. |
| service | string | | The service or application name. Resources will also be tagged with this name. |

