#!/bin/bash
set -euo pipefail
source /mnt/c/shellpractice/awscli/variable.sh
export AWS_PAGER=""

# Prompt for region and VPC ID
read -rp "Enter AWS region (default: us-east-1): " REGION
REGION=${REGION:-us-east-1}
# read -rp "Enter VPC ID to delete: " $VPC_ID
# VPC_ID is sourced from variable.sh

# Delete Auto Scaling Group

echo "Deleting Auto Scaling Group: $ASG_NAME"
ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" --query "AutoScalingGroups" --output text)
if [ -n "$ASG_EXISTS" ]; then
  aws autoscaling delete-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --force-delete \
    --region "$REGION"
else
  echo "Auto Scaling Group $ASG_NAME does not exist, skipping deletion."
fi

# Delete Launch Template
echo "Deleting Launch Template: $LAUNCH_TEMPLATE"
if aws ec2 describe-launch-templates --launch-template-names "$LAUNCH_TEMPLATE" --region "$REGION" --query "LaunchTemplates" --output text >/dev/null 2>&1; then
  aws ec2 delete-launch-template --launch-template-name "$LAUNCH_TEMPLATE" --region "$REGION"
  echo "Launch Template $LAUNCH_TEMPLATE deleted."
else
  echo "Launch Template $LAUNCH_TEMPLATE does not exist, skipping deletion."
fi

# Delete EC2 instances
echo "Terminating EC2 instances in VPC $VPC_ID..."
EC2_IDS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "Reservations[*].Instances[*].InstanceId" --output text)
if [ -n "$EC2_IDS" ]; then
  aws ec2 terminate-instances --instance-ids $EC2_IDS --region "$REGION"
  aws ec2 wait instance-terminated --instance-ids $EC2_IDS --region "$REGION"
  echo "Terminated EC2 instances: $EC2_IDS"
else
  echo "No EC2 instances found in VPC $VPC_ID, skipping termination."
fi

# Delete RDS instances
echo "Deleting RDS instances in VPC $VPC_ID..."
RDS_IDS=$(aws rds describe-db-instances --region "$REGION" --query "DBInstances[?DBSubnetGroup.VpcId=='$VPC_ID'].DBInstanceIdentifier" --output text)
if [ -n "$RDS_IDS" ]; then
  for RDS_ID in $RDS_IDS; do
    aws rds delete-db-instance --db-instance-identifier "$RDS_ID" --skip-final-snapshot --region "$REGION"
    aws rds wait db-instance-deleted --db-instance-identifier "$RDS_ID" --region "$REGION"
    echo "Deleted RDS instance: $RDS_ID"
  done
else
  echo "No RDS instances found in VPC $VPC_ID, skipping deletion."
fi

# Delete DB subnet group
if aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Deleting DB subnet group: $DB_SUBNET_GROUP_NAME"
  aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --region "$REGION"
  echo "Deleted DB subnet group: $DB_SUBNET_GROUP_NAME"
else
  echo "DB subnet group $DB_SUBNET_GROUP_NAME does not exist, skipping deletion."
fi

#delete target groups
echo "Deleting target groups in VPC $VPC_ID..."
TG_ARNs=$(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" --output text)
for TG_ARN in $TG_ARNs; do
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$REGION"
done    

# Delete load balancers
echo "Deleting load balancers in VPC $VPC_ID..."
LB_ARNs=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text)
for LB_ARN in $LB_ARNs; do
  aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN" --region "$REGION"
done



# Delete subnets
echo "Deleting all subnets in VPC $VPC_ID..."
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "Subnets[*].SubnetId" --output text)
for SUBNET_ID in $SUBNET_IDS; do
  aws ec2 delete-subnet --subnet-id "$SUBNET_ID" --region "$REGION"
done

# Delete security groups
echo "Deleting security groups in VPC $VPC_ID..."
SG_IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
for SG_ID in $SG_IDS; do
  aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"
done

# Detach and delete internet gateways
echo "Detaching and deleting internet gateways in VPC $VPC_ID..."
IGW_IDS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --region "$REGION" --query "InternetGateways[*].InternetGatewayId" --output text)
for IGW_ID in $IGW_IDS; do
  aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
  aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION"
done
echo "All subnets deleted for VPC $VPC_ID"

#Delete VPC
echo "Deleting VPC $VPC_ID..."
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION"
echo "VPC $VPC_ID deleted."

# Delete route tables (except main)
echo "Deleting non-main route tables in VPC $VPC_ID..."
RTB_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region "$REGION" --query "RouteTables[?Associations[0].Main!=true].RouteTableId" --output text)
for RTB_ID in $RTB_IDS; do
  ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$RTB_ID" --region "$REGION" --query "RouteTables[0].Associations[?Main==false].RouteTableAssociationId" --output text)
  for ASSOC_ID in $ASSOC_IDS; do
    aws ec2 disassociate-route-table --association-id "$ASSOC_ID" --region "$REGION"
  done
  aws ec2 delete-route-table --route-table-id "$RTB_ID" --region "$REGION"
  echo "Deleted route table $RTB_ID"
done

