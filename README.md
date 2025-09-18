# GitOps Platform - Blue-Green Deployment System

A container-based deployment platform implementing blue-green deployment patterns with automated infrastructure management.

## What It Does

- **Blue-green deployments** with zero-downtime switching
- **Database backup automation** before deployments
- **Cross-region disaster recovery** with S3 replication
- **Infrastructure monitoring** via CloudWatch dashboards
- **One-click rollback** when deployments fail

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │    │   Load          │    │   ECS Services  │
│   Pushes Image  │───▶│   Balancer      │───▶│   Blue/Green    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   CloudWatch    │    │   PostgreSQL    │
                       │   Monitoring    │    │   RDS Multi-AZ  │
                       └─────────────────┘    └─────────────────┘
```

## Tech Stack

- **Application**: Node.js + Express
- **Database**: PostgreSQL on RDS
- **Containers**: Docker + ECS Fargate
- **Infrastructure**: Terraform
- **Monitoring**: CloudWatch
- **Storage**: S3 with cross-region replication

## Project Structure

```
├── app.js                    # Main application
├── Dockerfile               # Container configuration
├── docker-compose.yml       # Local development
├── package.json             
├── public/
│   └── index.html           # Deployment dashboard
├── scripts/
│   ├── blue-green-deploy.sh # Deployment automation
│   ├── deploy.sh            # Build and deploy script
│   └── init-db.sql          # Database setup
└── terraform/               # Infrastructure as Code
    ├── main.tf              # Core infrastructure
    ├── ecs.tf               # Container services
    ├── database.tf          # RDS configuration
    ├── storage.tf           # S3 backup setup
    ├── monitoring.tf        # CloudWatch resources
    ├── variables.tf         # Configuration variables
    └── outputs.tf           # Resource outputs
```

## Quick Start

**Local Development:**
```bash
git clone <repository>
cd gitops-platform
npm install
docker-compose up
```

**Infrastructure Deployment:**
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**Application Deployment:**
```bash
./scripts/deploy.sh build
./scripts/deploy.sh deploy
```

## Key Features

**Blue-Green Deployment Process:**
1. Build new container image
2. Deploy to inactive environment (green)
3. Run health checks on new deployment
4. Switch load balancer traffic
5. Scale down old environment (blue)

**Automated Backup System:**
- RDS automated backups with 7-day retention
- Cross-region S3 replication for disaster recovery
- Pre-deployment database snapshots

**Monitoring Stack:**
- Application health checks at `/health` endpoint
- ECS service metrics (CPU, memory, task count)
- RDS performance monitoring
- Custom CloudWatch dashboard

## Infrastructure Components

- **VPC**: Isolated network with public/private subnets
- **ECS Cluster**: Fargate-based container orchestration
- **Application Load Balancer**: Traffic distribution with health checks
- **RDS Multi-AZ**: High-availability PostgreSQL database
- **S3 Buckets**: Primary and replica backup storage
- **CloudWatch**: Centralized logging and monitoring

## Security

- Containers run in private subnets
- Database connections use SSL encryption
- Secrets stored in AWS Secrets Manager
- Security groups restrict network access
- Non-root container execution

## Development Commands

```bash
npm start              # Start application locally
npm test              # Run test suite
docker-compose up     # Full local environment
./scripts/deploy.sh   # Deploy to AWS
terraform plan        # Preview infrastructure changes
```

## Requirements

- AWS account with appropriate IAM permissions
- Docker installed locally
- Node.js 18+ 
- Terraform (for infrastructure management)

## Performance Characteristics

- **Deployment time**: 8-12 minutes end-to-end
- **Recovery time**: Under 5 minutes with automated rollback
- **Database backup**: Automated daily snapshots
- **Container startup**: 30-60 seconds per instance

This platform demonstrates production deployment patterns including infrastructure automation, container orchestration, and disaster recovery procedures suitable for applications requiring high availability.
