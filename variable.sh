# variable.sh
VPC_ID=vpc-068e3b70ebef44a8c
EC2_NAME="neweraInstance"
InstanceId=$(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:Name,Values=$EC2_NAME" --query "Reservations[*].Instances[*].InstanceId" --output text)
EC2_SECURITY_GROUP_ID="sg-0a03f442de642f8a0"
REGION=us-east-1


##=====================INFRACOMPONENTS=====================

#########DB Configuration#########
DB_ENGINE=mysql
DB_VERSION="8.0.42"
DB_CLASS="db.t3.micro"
DB_NAME="databse"


AMI_ID="ami-08982f1c5bf93d976"
INSTANCE_TYPE="t3.micro"
KEY_PAIR="newkey"
SUBNET_IDS="subnet-01f15e48068475359 subnet-08ca7476c9afb3ae0"
AMI=ami-08982f1c5bf93d976
SSMROLE=ssmagentRole
CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
# Scaling configuration
ASG_NAME=MaASG
MIN_SIZE=1
MAX_SIZE=5
DESIRED_CAPACITY=2
SSMROLE=ssmagentRole


#================CONFIGURATION==========for LOAD BALANCER =============

REGION="us-east-1"
VPC_ID=vpc-068e3b70ebef44a8c
SUBNETS="subnet-01f15e48068475359 subnet-08ca7476c9afb3ae0"
SUBNET_ID=subnet-01f15e48068475359
SG_ID="sg-0a03f442de642f8a0"
LB_NAME="MyLoadBalancer"

##================CONFIGURATION==========For TARGET GROUP =============

TARGET_GROUP_NAME="MyTargetGroup"
LAUNCH_TEMPLATE="ASGLaunchTemplate"

