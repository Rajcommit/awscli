# variable.sh
EC2_NAME="fighing4it"
InstanceId="i-02869250b96a9576e"
EC2_SECURITY_GROUP_ID="sg-0b88ee672bdba3cf8"
REGION=us-east-1


##=====================INFRACOMPONENTS=====================
AMI_ID="ami-08982f1c5bf93d976"
INSTANCE_TYPE="t3.micro"
KEY_PAIR="newkey"
SUBNET_IDS="subnet-0d23389506da6c7bc subnet-06c3a1b38b5a446f0"
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
VPC_ID=vpc-09bd141db3cb07365
SUBNETS="subnet-04dbcd61235b7f94b subnet-0b15e9f0cb64bdf7b"
SG_ID="sg-0b88ee672bdba3cf8"
LB_NAME="MyLoadBalancer"

##================CONFIGURATION==========For TARGET GROUP =============

TARGET_GROUP_NAME="MyTargetGroup"
LAUNCH_TEMPLATE="ASGLaunchTemplate"


