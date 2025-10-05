# variable.sh
VPC_ID=vpc-01c7c81d30aa4acac
EC2_NAME="neweraInstances"
InstanceId=$(aws ec2 describe-instances --region us-east-1 --filters "Name=tag:Name,Values=$EC2_NAME" --query "Reservations[*].Instances[*].InstanceId" --output text)
EC2_SECURITY_GROUP_ID="sg-09c16eeee678df7e8"
REGION=us-east-1

#############s3-Bucket Configuration#############
BUCKET_NAME="newerabucket2026"





##=====================INFRACOMPONENTS=====================

#########DB Configuration#########
DB_ENGINE=mysql
DB_VERSION="8.0.42"
DB_CLASS="db.t3.micro"
DB_NAME="databse"


AMI_ID="ami-08982f1c5bf93d976"
INSTANCE_TYPE="t3.micro"
KEY_PAIR="newkey"
SUBNET_IDS="subnet-0ee29bfd460a81706 subnet-0373a98868bdbdd6a"
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

SUBNETS="subnet-0ee29bfd460a81706 subnet-0373a98868bdbdd6a"
SUBNET_ID=subnet-0ee29bfd460a81706
SG_ID="sg-0a03f442de642f8a0"
LB_NAME="MyLoadBalancer"

##================CONFIGURATION==========For TARGET GROUP =============

TARGET_GROUP_NAME="MyTargetGroup"
LAUNCH_TEMPLATE="ASGLaunchTemplates"

