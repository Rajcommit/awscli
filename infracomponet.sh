#!/bin/bash

source /mnt/c/shellpractice/awscli/variable.sh

set -euo pipefail  ##If the script fails , stopt the exectution

export AWS_PAGER=""  # prevent AWS CLI from opening a pager mid-script

IGW_NAME="rohuvpc"


##=======Gettinfg the subnet for better script flow=====================

#aws ec2 describe-subnets\
#    --filters "Name=vpc-id,Values=vpc-0fa1a62f8f61b0625" \
#    --query "Subnets[*].{SubnetId:SubnetId, CIDR: CidrBlock, AZ:AvailabilityZone, Name: Tags[?Key=='Name']|[0].Value}" \
#    --output text

APP_TIER_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values="$VPC_ID"" "Name=tag:Name,Values=AppSubnet" "Name=tag:Region,Values=us-east-1a"  --query "Subnets[*].SubnetId" --output text)
APP_TIER_B=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values="$VPC_ID"" "Name=tag:Name,Values=AppSubnet" "Name=tag:Region,Values=us-east-1b"  --query "Subnets[*].SubnetId" --output text )
DATA_TIER_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values="$VPC_ID"" "Name=tag:Name,Values=Datasubnet" "Name=tag:Region,Values=us-east-1a"  --query "Subnets[*].SubnetId" --output text)
DATA_TIER_B=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values="$VPC_ID"" "Name=tag:Name,Values=Datasubnet" "Name=tag:Region,Values=us-east-1b"  --query "Subnets[*].SubnetId" --output text )
PUB_TIER_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values="$VPC_ID"" "Name=tag:Name,Values=PublicSubnet" "Name=tag:Region,Values=us-east-1a"  --query "Subnets[*].SubnetId" --output text)

echo $APP_TIER_A
echo $APP_TIER_B
echo $DATA_TIER_A
echo $DATA_TIER_B
echo $PUB_TIER_A


CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)

###===========================Security-Group-creation====================================

####3333333EC2_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
####3333333    --group-name AllowAllSG \
####3333333    --description "Allow all inbound and outbound traffic for EC2" \
####3333333    --vpc-id $VPC_ID \
####3333333    --region $REGION \
####3333333    --query 'GroupId'  --output text )
####3333333
####3333333RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
####3333333    --group-name AllowRDSSG \
####3333333    --description "Allow all inbound and outbound traffic for RDS" \
####3333333    --vpc-id $VPC_ID \
####3333333    --region $REGION \
####3333333    --query 'GroupId'  --output text )
####3333333
echo -e "The created security-group-ID is: \033[0;32m$EC2_SECURITY_GROUP_ID\033[0m"


echo -e "The CIDR block for VPC \033[0;36m$VPC_ID\033[0m is \033[0;36m$CIDR\033[0m"

#3333aws ec2 authorize-security-group-ingress \
#3333    --group-id $EC2_SECURITY_GROUP_ID \
#3333    --protocol -1 \
#3333    --port -1 \
#3333    --cidr 0.0.0.0/0 \
#3333    --region $REGION
#3333
#3333
#3333aws ec2 authorize-security-group-ingress \
#3333    --group-id $RDS_SECURITY_GROUP_ID \
#3333    --protocol -1 \
#3333    --port -1 \
#3333    --cidr $CIDR \
#3333    --region $REGION
#3333

#aws ec2 authorize-security-group-ingress \
#    --group-id $EC2_SECURITY_GROUP_ID \
#    --protocol -1 \
#    --port -1 \
#    --cidr ::/0 \
#    --region $REGION

echo "All the ports are open now for sg: $EC2_SECURITY_GROUP_ID "

#aws ec2 authorize-security-group-egress \
#    --group-id $EC2_SECURITY_GROUP_ID \
#    --protocol -1 \
#    --port -1 \
#    --cidr 0.0.0.0/0 \
#    --region $REGION

#aws ec2 authorize-security-group-egress \
#    --group-id $EC2_SECURITY_GROUP_ID \
#    --protocol -1 \
#    --port -1 \
#    --cidr ::/0 \
#    --region $REGION
#
#aws ec2 authorize-security-group-egress \
#    --group-id $RDS_SECURITY_GROUP_ID \
#    --protocol -1 \
#    --port -1 \
#    --cidr 0.0.0.0/0 \
#    --region $REGION


###--------EC2 CONFIG--------------------


EC2_SECURITY_GROUP_ID="$EC2_SECURITY_GROUP_ID"
SUBNET_ID="$APP_TIER_A"

#read -rp "Enter the Instance_Name(default: neweraInstance): " EC2_NAME
#EC2_NAME=${EC2_NAME:-neweraInstance}
#
#echo "Instance name is : $EC2_NAME"

## RDS Config=====================
read -rp "Enter the RDS Name(default: rohurds): " RDS_NAME
RDS_NAME=${RDS_NAME:-rohurds}

DB_ENGINE=mysql
DB_VERSION="8.0.42"
DB_CLASS="db.t3.micro"
DB_NAME="databse"

read -rp "Enter the DB Username(default: rohini): " DB_USERNAME
DB_USERNAME=${DB_USERNAME:-rohurds}



#33333333333333while true; do
#33333333333333read -rsp "Enter the DB Password(default: redhatrohini): " DB_PASSWORD
#33333333333333echo
#33333333333333
#33333333333333DB_PASSWORD=${DB_PASSWORD:-redhatrohini}
#33333333333333
#33333333333333if [[ ${#DB_PASSWORD} -lt 8 ]]; then
#33333333333333    echo "Password must be at least 8 characters long. Please try again."
#33333333333333    continue
#33333333333333fi
#33333333333333read -rsp "Confirm Password: " DB_PASSWORD_CONFIRM
#33333333333333echo
#33333333333333if [[ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]]; then
#33333333333333    echo "Passwords do not match. Please try again."
#33333333333333   continue
#33333333333333fi
#33333333333333echo "Password accepted"
#33333333333333break
#33333333333333done
#33333333333333
#33333333333333DB_SECURITY_GROUP_NAME="default"
#33333333333333DB_SUBNET_GROUP_NAME="rohurdssubs"
#33333333333333SUBNET_IDS=( $DATA_TIER_A $DATA_TIER_B)
#33333333333333
#33333333333333echo "$SUBNET_ID"

# Enable DNS support
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames



#33333333333if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME"  --region "$REGION" >/dev/null 2>&1; then
#33333333333echo "Creating DB subnet group: $DB_SUBNET_GROUP_NAME"
#33333333333aws rds create-db-subnet-group \
#33333333333    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
#33333333333    --db-subnet-group-description "Rohisubs" \
#33333333333    --subnet-ids "${SUBNET_IDS[@]}" \
#33333333333    --region "$REGION" \
#33333333333    --query "DBSubnetGroup.DBSubnetGroupName" \
#33333333333    --output text
#33333333333echo "Createed DB subnetgroup: $DB_SUBNET_GROUP_NAME"
#33333333333else
#33333333333echo "Db subnet group $DB_SUBNET_GROUP_NAME already exists"
#33333333333fi
#33333333333echo "Createed DB subnetgroup: $DB_SUBNET_GROUP_NAME"


#########################Creating_RDS#######################################################

###33333333333aws rds create-db-instance \
###33333333333  --db-instance-identifier "$RDS_NAME" \
###33333333333  --db-instance-class "$DB_CLASS" \
###33333333333  --engine "$DB_ENGINE" \
###33333333333  --engine-version "$DB_VERSION" \
###33333333333  --allocated-storage 20 \
###33333333333  --master-username "$DB_USERNAME" \
###33333333333  --master-user-password "$DB_PASSWORD" \
###33333333333  --db-name "$DB_NAME" \
###33333333333  --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
###33333333333  --vpc-security-group-ids "$RDS_SECURITY_GROUP_ID" \
###33333333333  --backup-retention-period 1 \
###33333333333  --publicly-accessible \
###33333333333  --region "$REGION" \
###33333333333  --tags "Key=name,Value=${RDS_NAME}"
###33333333333
###33333333333################Waiting for the rds to come up#############################33
###33333333333
###33333333333echo "Waiting for Db to become avilable"
###33333333333aws rds wait db-instance-available --db-instance-identifier "$RDS_NAME" --region "$REGION"
###33333333333
###33333333333###=================Get the RDs endpoint########################
###33333333333
###33333333333DB_ENDPOINT=$( aws rds describe-db-instances --db-instance-identifier "$RDS_NAME" --region "$REGION"  --query "DBInstances[0].Endpoint.Address"  --output text )
###33333333333
###33333333333echo "RDS Instance ready at endpoint: $DB_ENDPOINT"
###33333333333

##===Creating the USer_Data===========

##=== Creating the User Data (with DB injected) ===========


cat > user_data.sh <<'EOF'
#!/bin/bash
set -euxo pipefail
curl -fsSL https://newerabucket2026.s3.us-east-1.amazonaws.com/userdataraw.sh -o /tmp/userdataraw.sh
bash /tmp/userdataraw.sh
EOF



############+==================================Create a lauch template yaml bases=============================############


##Encode the user data

USER_DATA_B64=$(base64 -w0 user_data.sh)


####=========Creatina yaml file for user data===================

cat > launch-template.yaml <<EOF
ImageId: ${AMI_ID}
InstanceType: ${INSTANCE_TYPE}
KeyName: ${KEY_PAIR}
IamInstanceProfile:
  Name: ${SSMROLE}
NetworkInterfaces:
  - AssociatePublicIpAddress: true
    DeviceIndex: 0
    SubnetId: ${SUBNET_ID}
    Groups:
      - ${EC2_SECURITY_GROUP_ID}
UserData: "${USER_DATA_B64}"
TagSpecifications:
  - ResourceType: instance
    Tags:
      - Key: Name
        Value: ${EC2_NAME}
      - Key: Environment
        Value: Dev
      - Key: Project
        Value: AutoInfra
EOF

echo " YAML Launch Template definition created at: launch-template.yaml"


# Convert YAML → JSON and create Launch Template
aws ec2 create-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE" \
  --version-description "v1 - WebApp with Apache, PHP, and RDS" \
  --launch-template-data "$(yq -o=json '.' launch-template.yaml)" \
  --region "$REGION"


echo " Launch Template '$LAUNCH_TEMPLATE' created successfully."


#===============CREATION-EC2-Instance============

 EC2_ID=$(aws ec2 run-instances \
    --launch-template LaunchTemplateName="$LAUNCH_TEMPLATE",Version="$LAUNCH_TEMPLATE_VERSION" \
    --region "$REGION" \
    --query 'Instances[0].InstanceId' \
    --output text)


##GET Public IP####

EC2_PUBLIC_IP=$( aws ec2 describe-instances  --instance-ids "$EC2_ID" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress"   --output text )


# ========= SUMMARY =========
echo "----------------------------------------"
echo " EC2 Instance ID : $EC2_ID"
echo " EC2 Public IP   : $EC2_PUBLIC_IP"
echo " RDS Endpoint    : $DB_ENDPOINT"
echo " Visit Website   : http://$EC2_PUBLIC_IP/"
echo " Congratulations! Your infrastructure is ready, Please run loadb.sh script next"
echo "----------------------------------------"