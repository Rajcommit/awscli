#!/bin/bash

source /mnt/c/shellpractice/awscli/variable.sh

set -euo pipefail

CHECKPOINT_FILE="/tmp/infracomponet.checkpoint"
STEP1_ENV="/tmp/infracomp.step1.env"
STEP2_ENV="/tmp/infracomp.step2.env"
STEP3_ENV="/tmp/infracomp.step3.env"

if [[ -f "$CHECKPOINT_FILE" ]]; then
  LAST_STEP=$(<"$CHECKPOINT_FILE")
else
  LAST_STEP=0
fi

if (( LAST_STEP >= 3 )) && [[ ! -f "$STEP3_ENV" ]]; then
  LAST_STEP=2
fi
if (( LAST_STEP >= 2 )) && [[ ! -f "$STEP2_ENV" ]]; then
  LAST_STEP=1
fi
if (( LAST_STEP >= 1 )) && [[ ! -f "$STEP1_ENV" ]]; then
  LAST_STEP=0
fi

for env_file in "$STEP1_ENV" "$STEP2_ENV" "$STEP3_ENV"; do
  [[ -f "$env_file" ]] && source "$env_file"
done

run_step() {
  local step="$1"; shift
  local label="$1"; shift
  if (( LAST_STEP < step )); then
    echo "===== Step ${step}: ${label} ====="
    if "$@"; then
      echo "$step" >"$CHECKPOINT_FILE"
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

  echo "App subnets: $APP_TIER_A $APP_TIER_B"
  echo "Data subnets: $DATA_TIER_A $DATA_TIER_B"
  echo "Public subnet: $PUB_TIER_A"

  CIDR=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)
  echo "VPC CIDR: $CIDR"

  EC2_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name AllowAllSG \
    --description "Allow all inbound and outbound traffic for EC2" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'GroupId' --output text)

  RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name AllowRDSSG \
    --description "Allow all inbound and outbound traffic for RDS" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress --group-id "$EC2_SECURITY_GROUP_ID" --protocol -1 --port -1 --cidr 0.0.0.0/0 --region "$REGION"
  aws ec2 authorize-security-group-ingress --group-id "$RDS_SECURITY_GROUP_ID" --protocol -1 --port -1 --cidr "$CIDR" --region "$REGION"

  SUBNET_ID="$APP_TIER_A"

  export APP_TIER_A APP_TIER_B DATA_TIER_A DATA_TIER_B PUB_TIER_A SUBNET_ID CIDR \
         EC2_SECURITY_GROUP_ID RDS_SECURITY_GROUP_ID

  cat >"$STEP1_ENV" <<ENV
export APP_TIER_A="${APP_TIER_A}"
export APP_TIER_B="${APP_TIER_B}"
export DATA_TIER_A="${DATA_TIER_A}"
export DATA_TIER_B="${DATA_TIER_B}"
export PUB_TIER_A="${PUB_TIER_A}"
export SUBNET_ID="${SUBNET_ID}"
export CIDR="${CIDR}"
export EC2_SECURITY_GROUP_ID="${EC2_SECURITY_GROUP_ID}"
export RDS_SECURITY_GROUP_ID="${RDS_SECURITY_GROUP_ID}"
ENV
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
      echo "Password must be at least 8 characters long."
      continue
    fi
    read -rsp "Confirm Password: " DB_PASSWORD_CONFIRM
    echo
    if [[ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]]; then
      echo "Passwords do not match."
      continue
    fi
    break
  done

  DB_SECURITY_GROUP_NAME="default"
  DB_SUBNET_GROUP_NAME="rohurdssubs"
  SUBNET_IDS=( "$DATA_TIER_A" "$DATA_TIER_B" )

  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames

  if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" --region "$REGION" >/dev/null 2>&1; then
    aws rds create-db-subnet-group \
      --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
      --db-subnet-group-description "Rohisubs" \
      --subnet-ids "${SUBNET_IDS[@]}" \
      --region "$REGION" \
      --query "DBSubnetGroup.DBSubnetGroupName" \
      --output text >/dev/null
  fi

  aws rds create-db-instance \
    --db-instance-identifier "$RDS_NAME" \
    --db-instance-class "$DB_CLASS" \
    --engine "$DB_ENGINE" \
    --engine-version "$DB_VERSION" \
    --allocated-storage 20 \
    --master-username "$DB_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
    --vpc-security-group-ids "$RDS_SECURITY_GROUP_ID" \
    --backup-retention-period 1 \
    --publicly-accessible \
    --region "$REGION" \
    --tags "Key=name,Value=${RDS_NAME}" >/dev/null

  echo "Waiting for DB instance to become available..."
  aws rds wait db-instance-available --db-instance-identifier "$RDS_NAME" --region "$REGION"

  DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "$RDS_NAME" --region "$REGION" --query "DBInstances[0].Endpoint.Address" --output text)
  echo "RDS endpoint: $DB_ENDPOINT"

  export RDS_NAME DB_USERNAME DB_PASSWORD DB_ENDPOINT DB_NAME

  cat >"$STEP2_ENV" <<ENV
export RDS_NAME="${RDS_NAME}"
export DB_USERNAME="${DB_USERNAME}"
export DB_PASSWORD="${DB_PASSWORD}"
export DB_ENDPOINT="${DB_ENDPOINT}"
export DB_NAME="${DB_NAME}"
ENV
}

step3_launch_template() {
  cat > user_data.sh <<'UD'
#!/bin/bash
set -euxo pipefail
curl -fsSL https://newerabucket2026.s3.us-east-1.amazonaws.com/userdataraw.sh -o /tmp/userdataraw.sh
bash /tmp/userdataraw.sh
UD

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

  aws ec2 create-launch-template \
    --launch-template-name "$LAUNCH_TEMPLATE" \
    --version-description "v1 - WebApp with Apache, PHP, and RDS" \
    --launch-template-data "$(yq -o=json '.' launch-template.yaml)" \
    --region "$REGION" >/dev/null || true

  LAUNCH_TEMPLATE_VERSION=$(aws ec2 describe-launch-template-versions \
    --launch-template-name "$LAUNCH_TEMPLATE" \
    --versions '$Latest' \
    --region "$REGION" \
    --query 'LaunchTemplateVersions[0].VersionNumber' \
    --output text)

  EC2_ID=$(aws ec2 run-instances \
    --launch-template LaunchTemplateName="$LAUNCH_TEMPLATE",Version="$LAUNCH_TEMPLATE_VERSION" \
    --region "$REGION" \
    --query 'Instances[0].InstanceId' \
    --output text)

  echo "Launched instance $EC2_ID"

  aws ec2 wait instance-running --instance-ids "$EC2_ID" --region "$REGION"

  EC2_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$EC2_ID" --region "$REGION" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
  TARGET_GROUP=$(aws elbv2 describe-target-groups --names "$TARGET_GROUP_NAME" --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text)

  echo "Instance public IP: $EC2_PUBLIC_IP"

  export LAUNCH_TEMPLATE_VERSION EC2_ID EC2_PUBLIC_IP TARGET_GROUP

  cat >"$STEP3_ENV" <<ENV
export LAUNCH_TEMPLATE_VERSION="${LAUNCH_TEMPLATE_VERSION}"
export EC2_ID="${EC2_ID}"
export EC2_PUBLIC_IP="${EC2_PUBLIC_IP}"
export TARGET_GROUP="${TARGET_GROUP}"
ENV
}

step4_asg_and_summary() {
  aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=$LAUNCH_TEMPLATE_VERSION" \
    --min-size "$MIN_SIZE" \
    --max-size "$MAX_SIZE" \
    --desired-capacity "$DESIRED_CAPACITY" \
    --vpc-zone-identifier "$SUBNET_ID" \
    --target-group-arns "$TARGET_GROUP" \
    --region "$REGION"

  aws autoscaling attach-instances \
    --instance-ids "$EC2_ID" \
    --auto-scaling-group-name "$ASG_NAME" \
    --region "$REGION"

  echo "----------------------------------------"
  echo " VPC ID           : $VPC_ID"
  echo " Security Group   : ${EC2_SECURITY_GROUP_ID:-<not set>}"
  echo " RDS Endpoint     : ${DB_ENDPOINT:-<not set>}"
  echo " EC2 Instance ID  : ${EC2_ID:-<not set>}"
  echo " EC2 Public IP    : ${EC2_PUBLIC_IP:-<not set>}"
  echo " Visit Website    : http://${EC2_PUBLIC_IP:-<not set>}/"
  echo "----------------------------------------"
}

run_step 1 "network and security groups" step1_network_and_security
run_step 2 "RDS creation" step2_create_rds
run_step 3 "user data and launch template" step3_launch_template
run_step 4 "auto scaling group" step4_asg_and_summary

echo "All steps completed."
rm -f "$CHECKPOINT_FILE" "$STEP3_ENV"
