# variable.sh
VPC_ID=vpc-09f622dd492ea0702
EC2_NAME="neweraInstances"

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
SUBNET_IDS="subnet-0f7f73e2bcce52b14 subnet-0fde8b40532ab1a9d"
AMI=ami-08982f1c5bf93d976
SSMROLE=ssmagentRole
LAUNCH_TEMPLATE=ASGLaunchTemplate
CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
# Scaling configuration
ASG_NAME=MaASG
MIN_SIZE=1
MAX_SIZE=5
DESIRED_CAPACITY=2
SSMROLE=ssmagentRole


#================CONFIGURATION==========for LOAD BALANCER =============

SUBNETS="subnet-0f7f73e2bcce52b14 subnet-0fde8b40532ab1a9d"
SUBNET_ID=subnet-0f7f73e2bcce52b14
SG_ID="sg-0a03f442de642f8a0"
LB_NAME="MyLoadBalancer"

##================CONFIGURATION==========For TARGET GROUP =============

TARGET_GROUP_NAME="MyTargetGroup"
LAUNCH_TEMPLATE="ASGLaunchTemplates"

