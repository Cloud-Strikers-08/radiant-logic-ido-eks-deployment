# Radiant Logic Identity Observability on AWS EKS

## Project Overview
Deploy Radiant Logic Identity Observability 3.1.0
on Amazon EKS.

## Environment
- AWS Region: ap-south-1
- Kubernetes Target: 1.34
- Infrastructure as Code: Terraform
- Container Orchestration: Kubernetes
- Package Manager: Helm 3
- Repository: GitHub

## Architecture
- AWS VPC
- Public and Private Subnets
- Amazon EKS
- EC2 Managed Node Groups
- Amazon EBS gp3
- Amazon S3
- IAM
- Ingress Controller

## Deployment Phases
1. Prerequisites
2. Infrastructure Provisioning
3. Kubernetes Configuration
4. Radiant Logic Installation
5. Application Validation
6. Infrastructure Cleanup

## Security
Never commit credentials, licence files,
private keys or Terraform state files.
