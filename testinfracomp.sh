#!/bin/bash

source /mnt/c/shellpractice/awscli/variable.sh

set -euo pipefail

CHECKPOINT_FILE="/tmp/infracomponet.checkpoint"
if [[ -f "$CHECKPOINT_FILE" ]]; then
  LAST_STEP=$(<"$CHECKPOINT_FILE")
else
  LAST_STEP=0
fi

run_step() {
  local step="$1"; shift
  local label="$1"; shift
  if (( LAST_STEP < step )); then
    echo "===== Step ${step}: ${label} ====="
    if "$@"; then
      echo "$step" > "$CHECKPOINT_FILE"
    else
      echo "Step ${step} failed. Leaving checkpoint." >&2
      exit 1
    fi
  else
    echo "Skipping step ${step} (${label}); already complete."
  fi
}

export AWS_PAGER=""

step1_network_and_security() {
  APP_TIER_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=AppSubnet" "Name=tag:Region,Values=us-east-1a" --query "Subnets[*].SubnetId" --output text)
  APP_TIER_B=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=AppSubnet" "Name=tag:Region,Values=us-east-1b" --query "Subnets[*].SubnetId" --output text)
  DATA_TIER_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=Datasubnet" "Name=tag:Region,Values=us-east-1a" --query "Subnets[*].SubnetId" --output text)
  DATA_TIER_B=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=Datasubnet" "Name=tag:Region,Values=us-east-1b" --query "Subnets[*].SubnetId" --output text)
  PUB_TIER_A=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=PublicSubnet" "Name=tag:Region,Values=us-east-1a" --query "Subnets[*].SubnetId" --output text)

  echo "$APP_TIER_A"
  echo "$APP_TIER_B"
  echo "$DATA_TIER_A"
  echo "$DATA_TIER_B"
  echo "$PUB_TIER_A"

  CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)

  EC2_SECURITY_GROUP_ID=$(aws ec2 create-security-group     --group-name AllowAllSG     --description "Allow all inbound and outbound traffic for EC2"     --vpc-id "$VPC_ID"     --region "$REGION"     --query 'GroupId' --output text)

  RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group     --group-name AllowRDSSG     --description "Allow all inbound and outbound traffic for RDS"     --vpc-id "$VPC_ID"     --region "$REGION"     --query 'GroupId' --output text)

  echo -e "The created security-group-ID is: [0;32m$EC2_SECURITY_GROUP_ID[0m"
  echo -e "The CIDR block for VPC [0;36m$VPC_ID[0m is [0;36m$CIDR[0m"

  aws ec2 authorize-security-group-ingress --group-id "$EC2_SECURITY_GROUP_ID" --protocol -1 --port -1 --cidr 0.0.0.0/0 --region "$REGION"
  aws ec2 authorize-security-group-ingress --group-id "$RDS_SECURITY_GROUP_ID" --protocol -1 --port -1 --cidr "$CIDR" --region "$REGION"

  echo "All the ports are open now for sg: $EC2_SECURITY_GROUP_ID"

  SUBNET_ID="$APP_TIER_A"

  export APP_TIER_A APP_TIER_B DATA_TIER_A DATA_TIER_B PUB_TIER_A SUBNET_ID CIDR          EC2_SECURITY_GROUP_ID RDS_SECURITY_GROUP_ID
}

step2_create_rds() {
  read -rp "Enter the RDS Name(default: rohurds): " RDS_NAME
  RDS_NAME=${RDS_NAME:-rohurds}

  DB_ENGINE=mysql
  DB_VERSION="8.0.42"
  DB_CLASS="db.t3.micro"
  DB_NAME="databse"

  read -rp "Enter the DB Username(default: rohini): " DB_USERNAME
  DB_USERNAME=${DB_USERNAME:-rohurds}

  while true; do
    read -rsp "Enter the DB Password(default: redhatrohini): " DB_PASSWORD
    echo
    DB_PASSWORD=${DB_PASSWORD:-redhatrohini}
    if [[ ${#DB_PASSWORD} -lt 8 ]]; then
      echo "Password must be at least 8 characters long. Please try again."
      continue
    fi
    read -rsp "Confirm Password: " DB_PASSWORD_CONFIRM
    echo
    if [[ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]]; then
      echo "Passwords do not match. Please try again."
      continue
    fi
    echo "Password accepted"
    break
  done

  DB_SECURITY_GROUP_NAME="default"
  DB_SUBNET_GROUP_NAME="rohurdssubs"
  SUBNET_IDS=( "$DATA_TIER_A" "$DATA_TIER_B" )

  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames

  if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Creating DB subnet group: $DB_SUBNET_GROUP_NAME"
    aws rds create-db-subnet-group       --db-subnet-group-name "$DB_SUBNET_GROUP_NAME"       --db-subnet-group-description "Rohisubs"       --subnet-ids "${SUBNET_IDS[@]}"       --region "$REGION"       --query "DBSubnetGroup.DBSubnetGroupName"       --output text
  else
    echo "Db subnet group $DB_SUBNET_GROUP_NAME already exists"
  fi

  aws rds create-db-instance     --db-instance-identifier "$RDS_NAME"     --db-instance-class "$DB_CLASS"     --engine "$DB_ENGINE"     --engine-version "$DB_VERSION"     --allocated-storage 20     --master-username "$DB_USERNAME"     --master-user-password "$DB_PASSWORD"     --db-name "$DB_NAME"     --db-subnet-group-name "$DB_SUBNET_GROUP_NAME"     --vpc-security-group-ids "$RDS_SECURITY_GROUP_ID"     --backup-retention-period 1     --publicly-accessible     --region "$REGION"     --tags "Key=name,Value=${RDS_NAME}"

  echo "Waiting for Db to become avilable"
  aws rds wait db-instance-available --db-instance-identifier "$RDS_NAME" --region "$REGION"

  DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$RDS_NAME" --region "$REGION" --query "DBInstances[0].Endpoint.Address" --output text)
  echo "RDS Instance ready at endpoint: $DB_ENDPOINT"

  export RDS_NAME DB_USERNAME DB_PASSWORD DB_ENDPOINT DB_NAME
}

step3_launch_template() {
  cat > user_data.sh <<'EOF'
#!/bin/bash
set -euxo pipefail
curl -fsSL https://newerabucket2026.s3.us-east-1.amazonaws.com/userdataraw.sh -o /tmp/userdataraw.sh
bash /tmp/userdataraw.sh
EOF

  USER_DATA_B64=$(base64 -w0 user_data.sh)

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

  aws ec2 create-launch-template     --launch-template-name "$LAUNCH_TEMPLATE"     --version-description "v1 - WebApp with Apache, PHP, and RDS"     --launch-template-data "$(yq -o=json '.' launch-template.yaml)"     --region "$REGION" || true

  LAUNCH_TEMPLATE_VERSION=$(aws ec2 describe-launch-template-versions     --launch-template-name "$LAUNCH_TEMPLATE"     --versions '$Latest'     --region "$REGION"     --query 'LaunchTemplateVersions[0].VersionNumber'     --output text)

  export LAUNCH_TEMPLATE_VERSION
  echo " Launch Template '$LAUNCH_TEMPLATE' ready (version $LAUNCH_TEMPLATE_VERSION)."
}

step4_asg_and_summary() {
  LAUNCH_TEMPLATE_VERSION="${LAUNCH_TEMPLATE_VERSION:-1}"

  aws autoscaling create-auto-scaling-group     --auto-scaling-group-name "$ASG_NAME"     --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=$LAUNCH_TEMPLATE_VERSION"     --min-size "$MIN_SIZE"     --max-size "$MAX_SIZE"     --desired-capacity "$DESIRED_CAPACITY"     --vpc-zone-identifier "$SUBNET_ID"     --region "$REGION"

  echo "Auto Scaling Group $ASG_NAME created with desired capacity $DESIRED_CAPACITY"

  echo "----------------------------------------"
  echo " VPC ID           : $VPC_ID"
  echo " Security Group   : $EC2_SECURITY_GROUP_ID"
  echo " RDS Endpoint     : ${DB_ENDPOINT:-<not set>}"
  echo " Launch Template  : $LAUNCH_TEMPLATE (v$LAUNCH_TEMPLATE_VERSION)"
  echo "----------------------------------------"
}

run_step 1 "network and security groups" step1_network_and_security
run_step 2 "RDS creation" step2_create_rds
run_step 3 "user data and launch template" step3_launch_template
run_step 4 "auto scaling group" step4_asg_and_summary

echo "All steps completed."
rm -f "$CHECKPOINT_FILE"
