#!/bin/bash
# scripts/deploy.sh
# Main deployment script for GitOps Platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="gitops-platform"
AWS_REGION="us-east-1"
ENVIRONMENT="dev"

echo -e "${BLUE}🚀 GitOps Platform Deployment Script${NC}"
echo "======================================"

# Check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}📋 Checking prerequisites...${NC}"
    
    commands=("aws" "terraform" "docker" "jq")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}❌ $cmd is not installed${NC}"
            exit 1
        else
            echo -e "${GREEN}✅ $cmd is installed${NC}"
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}❌ AWS credentials not configured${NC}"
        echo "Run: aws configure"
        exit 1
    else
        echo -e "${GREEN}✅ AWS credentials configured${NC}"
    fi
}

# Initialize Terraform
terraform_init() {
    echo -e "\n${YELLOW}🏗️  Initializing Terraform...${NC}"
    cd terraform
    
    if [ ! -f terraform.tfvars ]; then
        echo -e "${YELLOW}📝 Creating terraform.tfvars from example...${NC}"
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${YELLOW}⚠️  Please review and update terraform.tfvars before proceeding${NC}"
        read -p "Press Enter to continue after updating terraform.tfvars..."
    fi
    
    terraform init
    echo -e "${GREEN}✅ Terraform initialized${NC}"
}

# Plan Terraform deployment
terraform_plan() {
    echo -e "\n${YELLOW}📋 Planning Terraform deployment...${NC}"
    terraform plan -out=tfplan
    
    echo -e "\n${YELLOW}Review the plan above. Continue with deployment?${NC}"
    read -p "Type 'yes' to continue: " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${RED}❌ Deployment cancelled${NC}"
        exit 1
    fi
}

# Apply Terraform
terraform_apply() {
    echo -e "\n${YELLOW}🚀 Deploying infrastructure...${NC}"
    terraform apply tfplan
    echo -e "${GREEN}✅ Infrastructure deployed${NC}"
}

# Build and push Docker image
build_and_push() {
    echo -e "\n${YELLOW}🐳 Building and pushing Docker image...${NC}"
    
    # Get ECR repository URL
    ECR_REPO=$(terraform output -raw ecr_repository_url)
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Login to ECR
    echo -e "${YELLOW}🔐 Logging in to ECR...${NC}"
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # Build image
    echo -e "${YELLOW}🔨 Building Docker image...${NC}"
    cd ..
    docker build -t $PROJECT_NAME:latest .
    
    # Tag for ECR
    docker tag $PROJECT_NAME:latest $ECR_REPO:latest
    docker tag $PROJECT_NAME:latest $ECR_REPO:v1.0.0
    
    # Push to ECR
    echo -e "${YELLOW}📤 Pushing to ECR...${NC}"
    docker push $ECR_REPO:latest
    docker push $ECR_REPO:v1.0.0
    
    echo -e "${GREEN}✅ Docker image pushed to ECR${NC}"
    cd terraform
}

# Update ECS service
update_ecs_service() {
    echo -e "\n${YELLOW}🔄 Updating ECS service...${NC}"
    
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    SERVICE_NAME="${PROJECT_NAME}-blue"
    
    # Force new deployment
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force-new-deployment \
        --region $AWS_REGION
    
    echo -e "${GREEN}✅ ECS service updated${NC}"
}

# Display deployment info
show_deployment_info() {
    echo -e "\n${GREEN}🎉 Deployment completed successfully!${NC}"
    echo "=================================="
    
    ALB_URL=$(terraform output -raw application_url)
    echo -e "🌐 Application URL: ${BLUE}$ALB_URL${NC}"
    echo -e "📊 AWS Console: https://console.aws.amazon.com/ecs/home?region=$AWS_REGION"
    echo -e "📈 CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION"
    
    echo -e "\n${YELLOW}⏳ Note: It may take 5-10 minutes for the application to be fully available${NC}"
    echo -e "${YELLOW}💡 Monitor the ECS service in AWS Console for deployment progress${NC}"
}

# Main deployment flow
main() {
    case "$1" in
        "init")
            check_prerequisites
            terraform_init
            ;;
        "plan")
            terraform_plan
            ;;
        "apply")
            terraform_apply
            ;;
        "build")
            build_and_push
            ;;
        "deploy")
            update_ecs_service
            ;;
        "full")
            check_prerequisites
            terraform_init
            terraform_plan
            terraform_apply
            build_and_push
            update_ecs_service
            show_deployment_info
            ;;
        "destroy")
            echo -e "${RED}🗑️  Destroying infrastructure...${NC}"
            terraform destroy
            ;;
        *)
            echo "Usage: $0 {init|plan|apply|build|deploy|full|destroy}"
            echo ""
            echo "Commands:"
            echo "  init     - Initialize Terraform"
            echo "  plan     - Plan Terraform deployment"
            echo "  apply    - Apply Terraform changes"
            echo "  build    - Build and push Docker image"
            echo "  deploy   - Update ECS service"
            echo "  full     - Run complete deployment"
            echo "  destroy  - Destroy all infrastructure"
            exit 1
            ;;
    esac
}

main "$@"