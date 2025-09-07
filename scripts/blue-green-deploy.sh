#!/bin/bash
# scripts/blue-green-deploy.sh
# Blue-Green deployment script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_NAME="gitops-platform"
AWS_REGION="us-east-1"

echo -e "${BLUE}🔄 Blue-Green Deployment Script${NC}"
echo "================================"

# Get current active service
get_active_service() {
    LISTENER_ARN=$(aws elbv2 describe-listeners \
        --load-balancer-arn $(aws elbv2 describe-load-balancers \
        --names "${PROJECT_NAME}-alb" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    ACTIVE_TG=$(aws elbv2 describe-listeners \
        --listener-arns $LISTENER_ARN \
        --query 'Listeners[0].DefaultActions[0].TargetGroupArn' \
        --output text)
    
    if [[ $ACTIVE_TG == *"blue"* ]]; then
        echo "blue"
    else
        echo "green"
    fi
}

# Deploy to inactive environment
deploy_to_inactive() {
    ACTIVE=$(get_active_service)
    
    if [ "$ACTIVE" = "blue" ]; then
        INACTIVE="green"
        INACTIVE_TG_ARN=$(cd terraform && terraform output -raw green_target_group_arn)
    else
        INACTIVE="blue"
        INACTIVE_TG_ARN=$(cd terraform && terraform output -raw blue_target_group_arn)
    fi
    
    echo -e "${YELLOW}📊 Current active service: ${ACTIVE}${NC}"
    echo -e "${YELLOW}🎯 Deploying to: ${INACTIVE}${NC}"
    
    # Scale up inactive service
    echo -e "${YELLOW}📈 Scaling up ${INACTIVE} service...${NC}"
    aws ecs update-service \
        --cluster "${PROJECT_NAME}-cluster" \
        --service "${PROJECT_NAME}-${INACTIVE}" \
        --desired-count 2 \
        --region $AWS_REGION
    
    # Wait for service to be healthy
    echo -e "${YELLOW}⏳ Waiting for ${INACTIVE} service to be healthy...${NC}"
    aws ecs wait services-stable \
        --cluster "${PROJECT_NAME}-cluster" \
        --services "${PROJECT_NAME}-${INACTIVE}" \
        --region $AWS_REGION
    
    # Check target group health
    echo -e "${YELLOW}🔍 Checking target group health...${NC}"
    for i in {1..30}; do
        HEALTHY_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn $INACTIVE_TG_ARN \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
            --output text)
        
        if [ "$HEALTHY_COUNT" -ge "2" ]; then
            echo -e "${GREEN}✅ ${INACTIVE} service is healthy${NC}"
            break
        fi
        
        echo "Waiting for healthy targets... ($i/30)"
        sleep 10
    done
    
    if [ "$HEALTHY_COUNT" -lt "2" ]; then
        echo -e "${RED}❌ ${INACTIVE} service failed health checks${NC}"
        exit 1
    fi
}

# Switch traffic
switch_traffic() {
    ACTIVE=$(get_active_service)
    
    if [ "$ACTIVE" = "blue" ]; then
        NEW_TG_ARN=$(cd terraform && terraform output -raw green_target_group_arn)
        NEW_SERVICE="green"
        OLD_SERVICE="blue"
    else
        NEW_TG_ARN=$(cd terraform && terraform output -raw blue_target_group_arn)
        NEW_SERVICE="blue"
        OLD_SERVICE="green"
    fi
    
    echo -e "${YELLOW}🔄 Switching traffic from ${ACTIVE} to ${NEW_SERVICE}...${NC}"
    
    # Get listener ARN
    LISTENER_ARN=$(aws elbv2 describe-listeners \
        --load-balancer-arn $(aws elbv2 describe-load-balancers \
        --names "${PROJECT_NAME}-alb" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    # Update listener to point to new target group
    aws elbv2 modify-listener \
        --listener-arn $LISTENER_ARN \
        --default-actions Type=forward,TargetGroupArn=$NEW_TG_ARN \
        --region $AWS_REGION
    
    echo -e "${GREEN}✅ Traffic switched to ${NEW_SERVICE}${NC}"
    
    # Wait a bit, then scale down old service
    echo -e "${YELLOW}⏳ Waiting 60 seconds before scaling down ${OLD_SERVICE}...${NC}"
    sleep 60
    
    echo -e "${YELLOW}📉 Scaling down ${OLD_SERVICE} service...${NC}"
    aws ecs update-service \
        --cluster "${PROJECT_NAME}-cluster" \
        --service "${PROJECT_NAME}-${OLD_SERVICE}" \
        --desired-count 0 \
        --region $AWS_REGION
    
    echo -e "${GREEN}🎉 Blue-Green deployment completed!${NC}"
}

# Rollback function
rollback() {
    echo -e "${RED}🔙 Rolling back deployment...${NC}"
    
    ACTIVE=$(get_active_service)
    
    if [ "$ACTIVE" = "blue" ]; then
        ROLLBACK_TG_ARN=$(cd terraform && terraform output -raw green_target_group_arn)
        ROLLBACK_SERVICE="green"
    else
        ROLLBACK_TG_ARN=$(cd terraform && terraform output -raw blue_target_group_arn)
        ROLLBACK_SERVICE="blue"
    fi
    
    # Scale up the other service
    aws ecs update-service \
        --cluster "${PROJECT_NAME}-cluster" \
        --service "${PROJECT_NAME}-${ROLLBACK_SERVICE}" \
        --desired-count 2 \
        --region $AWS_REGION
    
    # Wait for it to be healthy
    aws ecs wait services-stable \
        --cluster "${PROJECT_NAME}-cluster" \
        --services "${PROJECT_NAME}-${ROLLBACK_SERVICE}" \
        --region $AWS_REGION
    
    # Switch traffic back
    LISTENER_ARN=$(aws elbv2 describe-listeners \
        --load-balancer-arn $(aws elbv2 describe-load-balancers \
        --names "${PROJECT_NAME}-alb" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    aws elbv2 modify-listener \
        --listener-arn $LISTENER_ARN \
        --default-actions Type=forward,TargetGroupArn=$ROLLBACK_TG_ARN \
        --region $AWS_REGION
    
    echo -e "${GREEN}✅ Rollback completed${NC}"
}

# Main function
main() {
    case "$1" in
        "deploy")
            deploy_to_inactive
            switch_traffic
            ;;
        "switch")
            switch_traffic
            ;;
        "rollback")
            rollback
            ;;
        "status")
            ACTIVE=$(get_active_service)
            echo -e "Current active service: ${GREEN}${ACTIVE}${NC}"
            ;;
        *)
            echo "Usage: $0 {deploy|switch|rollback|status}"
            echo ""
            echo "Commands:"
            echo "  deploy   - Deploy to inactive environment and switch traffic"
            echo "  switch   - Switch traffic between blue and green"
            echo "  rollback - Rollback to previous version"
            echo "  status   - Show current active service"
            exit 1
            ;;
    esac
}

main "$@"