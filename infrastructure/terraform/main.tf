# Hitachi Penske Vehicle Telematics Platform - AWS Infrastructure

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "penske-terraform-state"
    key            = "telematics/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Penske Vehicle Telematics"
      Client      = "Penske Truck Leasing"
      ManagedBy   = "Terraform"
      Environment = var.environment
      CostCenter  = "Engineering"
      Owner       = "Hitachi Data Team"
    }
  }
}

# VPC Configuration
module "vpc" {
  source = "./modules/vpc"
  
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
}

# MSK (Managed Streaming for Kafka)
module "msk" {
  source = "./modules/msk"
  
  cluster_name       = "penske-kafka-${var.environment}"
  kafka_version      = "3.5.1"
  number_of_brokers  = 3
  instance_type      = var.kafka_instance_type
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  environment        = var.environment
}

# EMR for Spark/Flink
module "emr" {
  source = "./modules/emr"
  
  cluster_name      = "penske-emr-${var.environment}"
  release_label     = "emr-6.14.0"
  master_type       = var.emr_master_instance_type
  core_type         = var.emr_core_instance_type
  core_count        = var.emr_core_instance_count
  vpc_id            = module.vpc.vpc_id
  subnet_id         = module.vpc.private_subnet_ids[0]
  environment       = var.environment
}

# S3 Data Lake
module "s3" {
  source = "./modules/s3"
  
  bucket_prefix = "penske-datalake"
  environment   = var.environment
  
  lifecycle_rules = {
    raw = {
      transition_days = 30
      expiration_days = 90
    }
    processed = {
      transition_days = 90
      expiration_days = 365
    }
  }
}

# Redshift
module "redshift" {
  source = "./modules/redshift"
  
  cluster_identifier  = "penske-redshift-${var.environment}"
  node_type           = var.redshift_node_type
  number_of_nodes     = var.redshift_node_count
  database_name       = "penske_analytics"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  environment         = var.environment
}

# Outputs
output "msk_bootstrap_brokers" {
  value     = module.msk.bootstrap_brokers
  sensitive = true
}

output "s3_data_lake_buckets" {
  value = module.s3.bucket_names
}

output "emr_master_public_dns" {
  value = module.emr.master_public_dns
}