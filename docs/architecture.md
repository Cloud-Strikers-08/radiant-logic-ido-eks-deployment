# Radiant Logic IDO Architecture

Developer
   |
   v
GitHub
   |
   v
Terraform
   |
   v
AWS VPC
   |
   +-- Public Subnets
   |
   +-- Private Subnets
          |
          v
       Amazon EKS
          |
          +-- Worker Node 1
          +-- Worker Node 2
          +-- Worker Node 3
          |
          +-- Radiant Logic Shared Services
          +-- Identity Data Platform

Storage:
   +-- Amazon EBS gp3
   +-- Amazon S3

Region: ap-south-1
