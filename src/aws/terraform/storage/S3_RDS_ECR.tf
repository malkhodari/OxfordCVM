# store the state of the terraform project in AWS S3
# comment out to store locally
# terraform {
#     backend "s3" {
#         bucket = "cti-ukb-tf-state"
#         key    = "state.tfstate"
#     }
# }

# define platform (when running with aws CLI)
provider "aws" {
    profile = "default"
    region  = "us-east-1"
}

data "aws_availability_zones" "available_zones" {
    state = "available"
}

# S3 configuration
#   AWS free tier (as of 15-09-2022):
#   - 5GB standard storage
#   - 20,000 GET requests per month
#   - 2,000 PUT/COPY/POST/LIST requests per month
#   - 100 GB data transfer out each month

resource "aws_s3_bucket" "s3_bucket_name" {
    bucket = "cti-ukb-data"
    tags = {
        Name        = "cti-ukb-data"
        Environment = "dev"
    }
}

resource "aws_s3_object" "s3_object" {
    bucket = aws_s3_bucket.s3_bucket_name.id
    key    = "dvc"
}

resource "aws_s3_bucket_acl" "s3_acl" {
    bucket = aws_s3_bucket.s3_bucket_name.id
    acl    = "private"
}

resource "aws_s3_bucket_versioning" "s3_version" {
    bucket = aws_s3_bucket.s3_bucket_name.id
    versioning_configuration {
        status = "Disabled"
    }
}

resource "aws_s3_bucket_public_access_block" "s3_access" {
    bucket                  = aws_s3_bucket.s3_bucket_name.id
    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
}

# RDS configuration
#   AWS free tier (as of 15-09-2022):
#   - 20 GB of General Purpose (SSD) DB Storage
#   - 20 GB of backup storage for your automated database backups and 
#     any user-initiated DB snapshots
#   - 750 hours of Single-AZ db.t2.micro/db.t3.micro/db.t4g.micro Instances 
#     for MySQL/MariaDB/PostgreSQL per month
#   - If running more than one instance, usage is aggregated across all instance
#   - 750 hours of RDS Single-AZ db.t2.micro Instance usage running SQL Server 
#     (running SQL Server Express Edition) per month

resource "aws_db_instance" "rds_postgresql_name" {
    engine                              = "postgres"
    engine_version                      = "13.7"
    instance_class                      = "db.t2.micro"
    identifier                          = "ukb-db"
    db_name                             = "ukb_postgres_db"
    username                            = "zhaohanxiong_rds_username"
    password                            = "zhaohanxiong_rds_password"
    publicly_accessible                 = false
    skip_final_snapshot                 = true
    multi_az                            = true
    allocated_storage                   = 10
    port                                = 5432
    iam_database_authentication_enabled = false
    db_subnet_group_name                = aws_db_subnet_group.db_subnet_group.id
    vpc_security_group_ids              = [aws_security_group.rds_sg.id, aws_security_group.ecs_sg.id]
    final_snapshot_identifier           = "ukb-db-final"
}

# ECR configuration
#   AWS free tier (as of 15-09-2022):
#   - 500 MB per month of storage for private repositories
#   - 50 GB of free storage for public repositories
#   - No cost transferring data in to private or public repositories
#   - Anonymously (without using an AWS account) transfer 500 GB of data to the 
#     Internet from a public repository each month
#   - If you authenticate to Amazon ECR with an existing AWS account, you can  
#     transfer 5 TB of data to the Internet from a public repository each month
#   - Unlimited bandwidth at no cost when transferring data from a public repository 
#     to AWS compute resources in any AWS Region.

# create public elastic container repo
resource "aws_ecrpublic_repository" "ecr_name" {
    repository_name = "cti-pred"
}

resource "aws_ecrpublic_repository_policy" "ecr_name" {
    repository_name = aws_ecrpublic_repository.ecr_name.repository_name
    policy = <<EOF
        {
            "Version": "2008-10-17",
            "Statement": [
                {
                    "Sid": "new policy",
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": [
                        "ecr:GetDownloadUrlForLayer",
                        "ecr:BatchGetImage",
                        "ecr:BatchCheckLayerAvailability",
                        "ecr:PutImage",
                        "ecr:InitiateLayerUpload",
                        "ecr:UploadLayerPart",
                        "ecr:CompleteLayerUpload",
                        "ecr:DescribeRepositories",
                        "ecr:GetRepositoryPolicy",
                        "ecr:ListImages",
                        "ecr:DeleteRepository",
                        "ecr:BatchDeleteImage",
                        "ecr:SetRepositoryPolicy",
                        "ecr:DeleteRepositoryPolicy"
                    ]
                }
            ]
        }
        EOF
}

# resource "aws_ecr_repository" "ecr_name" {
#     name                 = "cti-pred"
#     image_tag_mutability = "MUTABLE"
#     image_scanning_configuration {
#         scan_on_push = true
#     }
# }

# Output parameter of provisioned component 
output "postgresql_endpoint" {
    value = aws_db_instance.rds_postgresql_name.endpoint
}

output "ecr_repository_worker_endpoint" {
    value = aws_ecrpublic_repository.ecr_name.repository_uri
}
