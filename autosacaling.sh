#!/bin/bash

source /mnt/c/shellpractice/loadb.sh

set -euo pipefail

source /mnt/c/shellpractice/variable.sh

export AWS_PAGER=""

read -rp "Enter the name of Launch Template (default: ASGLaunchTemplate): " LAUNCH_TEMPLATE
LAUNCH_TEMPLATE=${LAUNCH_TEMPLATE:-ASGLaunchTemplate}

read -rp "Enter AWS region (default: us-east-1): " REGION
REGION=${REGION:-us-east-1}

KEY_PAIR=$(aws ec2 describe-instances --instance-ids "$InstanceId" --region "$REGION" --query 'Reservations[0].Instances[0].KeyName' --output text)
INSTANCE_TYPE=$(aws ec2 describe-instances --instance-ids "$InstanceId" --region "$REGION" --query 'Reservations[0].Instances[0].InstanceType' --output text)

if [ "$KEY_PAIR" = "None" ]; then
  KEY_PAIR=""
fi

if [ -z "$INSTANCE_TYPE" ] || [ "$INSTANCE_TYPE" = "None" ]; then
  echo "Unable to determine instance type for instance $InstanceId in region $REGION."
  exit 1
fi

echo "Creating Launch Template: $LAUNCH_TEMPLATE"

aws ec2 create-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE" \
  --version-description "Initial_Version" \
  --launch-template-data "$(aws ec2 describe-instances --instance-ids "$InstanceId" --region "$REGION" --query 'Reservations[0].Instances[0]' --output json)" \
  --region "$REGION"

echo "Launch Template $LAUNCH_TEMPLATE created."

LATEST_VERSION=$(aws ec2 create-launch-template-version \
  --launch-template-name "$LAUNCH_TEMPLATE" \
  --source-version 1 \
  --version-description "Associate public IPv4" \
  --launch-template-data '{
    "NetworkInterfaces": [
      {
        "DeviceIndex": 0,
        "AssociatePublicIpAddress": true
      }
    ]
  }' \
  --region "$REGION" \
  --query 'LaunchTemplateVersion.VersionNumber' \
  --output text)

echo "Launch Template version $LATEST_VERSION adds public IPv4 association."

echo "Creating Auto Scaling Group: $ASG_NAME"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=$LATEST_VERSION" \
  --min-size "$MIN_SIZE" \
  --max-size "$MAX_SIZE" \
  --desired-capacity "$DESIRED_CAPACITY" \
  --vpc-zone-identifier "$SUBNET_IDS" \
  --target-group-arns "$TARGET_GROUP" \
  --region "$REGION"

aws autoscaling attach-instances \
  --instance-ids "$InstanceId" \
  --auto-scaling-group-name "$ASG_NAME" \
  --region "$REGION"

echo "Auto Scaling Group $ASG_NAME created with desired capacity $DESIRED_CAPACITY"
