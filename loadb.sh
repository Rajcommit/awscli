#!/bin/bash


source /mnt/c/shellpractice/variable.sh
set -euo pipefail

##=== Configuration  =======

#=============Create Target Group =================


echo "Creating =======Target Group=============="

echo

TARGET_GROUP=$(aws elbv2 create-target-group \
 --name "$TARGET_GROUP_NAME" \
 --protocol HTTP \
 --port 80 \
 --vpc-id "$VPC_ID" \
 --health-check-protocol HTTP \
 --health-check-port 80 \
 --health-check-path / \
 --target-type instance \
 --region $REGION \
 --query 'TargetGroups[0].TargetGroupArn' \
 --output text ) 

echo "The created Target Group ARN is: $TARGET_GROUP"



#=============Create LoadBalancer =================


echo "Creating =======LoadBalancer=============="

echo

Load_BALANCER=$(aws elbv2 create-load-balancer \
 --name $LB_NAME --subnets $SUBNET_IDS \
 --security-groups $EC2_SECURITY_GROUP_ID  \
 --scheme internet-facing \
 --region $REGION \
 --type application \
 --ip-address-type ipv4 \
 --query 'LoadBalancers[0].LoadBalancerArn' \
 --output text ) 
 
 echo "The created Load Balancer ARN is: $Load_BALANCER"


#=============  Listerner =================

echo "Creating =======Listerner=============="

echo

LISTNER=$(aws elbv2 create-listener --load-balancer-arn $Load_BALANCER --protocol HTTP --port 80 \
 --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP --region $REGION \
 --query 'Listeners[0].ListenerArn' \
 --output text )

 echo "The created Listener ARN is: $LISTNER"





