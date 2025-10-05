#!/bin/bash
set -euo pipefail

source /mnt/c/shellpractice/awscli/variable.sh

export AWS_PAGER=""

read -rp "Enter the name of Launch Template (default: ASGLaunchTemplate): " LAUNCH_TEMPLATE
LAUNCH_TEMPLATE=${LAUNCH_TEMPLATE:-ASGLaunchTemplate}

read -rp "Enter AWS region (default: us-east-1): " REGION
REGION=${REGION:-us-east-1}

echo "Creating Launch Template: $LAUNCH_TEMPLATE"

LAUNCH_TEMPLATE_PAYLOAD=$(mktemp)  ##make a temp file to store the launch template data
cleanup_payload() {
  rm -f "$LAUNCH_TEMPLATE_PAYLOAD"
}
trap cleanup_payload EXIT ## ensure temp file is removed on script exit

aws ec2 get-launch-template-data \
  --instance-id "$InstanceId" \
  --region "$REGION" \
  --query 'LaunchTemplateData' \
  --output json | jq 'del(.Placement.AvailabilityZoneId, .PrivateIpAddresses, .NetworkInterfaces[].PrivateIpAddresses)' >"$LAUNCH_TEMPLATE_PAYLOAD"

if ! [ -s "$LAUNCH_TEMPLATE_PAYLOAD" ]; then
  echo "Unable to capture launch template data from instance $InstanceId."
  exit 1
fi

aws ec2 create-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE" \
  --version-description "Initial_Version" \
  --launch-template-data file://"$LAUNCH_TEMPLATE_PAYLOAD" \
  --tag-specifications "ResourceType=launch-template,Tags=[{Key=Name,Value=${EC2_NAME}},{Key=Region,Value=${REGION}}]" \
  --region "$REGION"

echo " Launch Template $LAUNCH_TEMPLATE created."

echo "Creating Auto Scaling Group: $ASG_NAME"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=1" \
  --min-size $MIN_SIZE \
  --max-size $MAX_SIZE \
  --desired-capacity $DESIRED_CAPACITY \
  --vpc-zone-identifier "$SUBNET_IDS" \
  --region "$REGION"

aws autoscaling attach-instances \
  --instance-ids "$InstanceId" \
  --auto-scaling-group-name "$ASG_NAME" \
  --region "$REGION"

echo "Auto Scaling Group $ASG_NAME created with desired capacity $DESIRED_CAPACITY"
