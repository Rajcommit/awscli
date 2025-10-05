#!/bin/bash
set -euo pipefail
source /mnt/c/shellpractice/awscli/variable.sh

##===============CONFIGURATION==========

##Creating region 

read -rp "Enter AWS region (default: us-east-1): " REGION
REGION=${REGION:-us-east-1}


##Creating the IGW
read -rp "Enter IGW_NAME (default: NewIGA): " IGW_NAME
IGW_NAME=${IGW_NAME:-NewIGA}


read -rp "Enter the first app_tier-Id: " APP_TIER_A
read -rp "Enter the second app_tier-Id: " APP_TIER_B


#============================CREATE IGW=======================

echo "Creating Internet Gateway......"

IGW_ID=$( aws ec2 create-internet-gateway  --region "$REGION" --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value="$IGW_NAME"},{Key=Region,Value=us-east-1}]" --query 'InternetGateway.InternetGatewayId' --output text ) && echo "The created Internet Gateway Id is: $IGW_ID"

##===============Attach IGW To VPC=====================
echo "Attaching Internet_Gateway $IGW_ID to VPC $VPC_ID...."

aws ec2 attach-internet-gateway   --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region $REGION

echo "Internet Gateway $IGW_NAME with $IGW_ID is sucessfully attached to VPC $VPC_ID"

##aws ec2 attach-internet-gateway --vpc-id "vpc-02bb693fd93382c2c" --internet-gateway-id "igw-0ea8aabdfa4ad17fb" --region us-east-1

RTB_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region $REGION \
  --query "RouteTables[*].RouteTableId" \
  --output text)
  ## this is not future proof what the fuck if there are multiple route tables, who will take care of that dude
  #  --subnet-id $APP_TIER_A

  echo  "The createad Routetable ID is $RTB_ID and now we will create attach IGW to the PRIVATE_SUBNET"

  aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION

  echo "The $IGW_NAME is attached with All subnets now please trigget the infracomponet.sh please"