#!/bin/bash

source /mnt/c/shellpractice/loadb.sh

set -euo pipefail  ## If the script fails, it will exit immediately

source /mnt/c/shellpractice/variable.sh

export AWS_PAGER=""   ## disable CLI pager so script runs non-interactively
##==============Variable for Launch Template==================

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


#================== Update with your VPC subnet IDs ================


#ensure_sg_id() {
#  local sg_id
#
#  sg_id=$(aws ec2 describe-security-groups --group-ids "$sg_id" --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null || true)
#
#  if [ -z "$sg_id" ] || [ "$sg_id" = "None" ]; then
#    echo "Security group $lookup_value not found. Please create it first."
#    exit 1
#  fi
#
#  echo "The security group existing id is: $sg_id"
#  SECURITY_GROUP_ID="$sg_id"
#}
#ensure_sg_id "$EC2_SECURITY_GROUP_ID"
#
#
#### Encode user data file
##USERDATA=$(base64 -w0 user_data.sh) ## -w0 to avoid line breaks in the output

#============Creating Launch Template==============


echo "Creating Launch Template: $LAUNCH_TEMPLATE"


##Tags for future refrence

TAGS=$(aws ec2 describe-tags --filters "Name=resource-id, Values=$InstanceId"  --query 'Tags[].{Key:Key,Value:Value}' --output json )

aws ec2 create-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE" \
  --version-description "Initial_Version" \
  --launch-template-data "$(aws ec2 describe-instances --instance-ids $InstanceId --query 'Reservations[0].Instances[0]' --output json)" \
  --region "$REGION"


echo " Launch Template $LAUNCH_TEMPLATE created."

jq 'del(.Placement.AvailabilityZoneId)'


##==============Create Auto Scaling Group==================

echo "Creating Auto Scaling Group: $ASG_NAME"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=1" \
  --min-size $MIN_SIZE \
  --max-size $MAX_SIZE \
  --desired-capacity $DESIRED_CAPACITY \
  --vpc-zone-identifier "$SUBNET_IDS" \
  --target-group-arns "$TARGET_GROUP" \
  --region "$REGION"



aws autoscaling attach-instances \
  --instance-ids "$InstanceId" \
  --auto-scaling-group-name "$ASG_NAME" \
  --region "$REGION"

echo "Auto Scaling Group $ASG_NAME created with desired capacity $DESIRED_CAPACITY"
