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

EC2_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name AllowAllSG \
    --description "Allow all inbound and outbound traffic for EC2" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --query 'GroupId'  --output text )

RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name AllowRDSSG \
    --description "Allow all inbound and outbound traffic for RDS" \
    --vpc-id $VPC_ID \
    --region $REGION \
    --query 'GroupId'  --output text )

echo -e "The created security-group-ID is: \033[0;32m$EC2_SECURITY_GROUP_ID\033[0m"


echo -e "The CIDR block for VPC \033[0;36m$VPC_ID\033[0m is \033[0;36m$CIDR\033[0m"

aws ec2 authorize-security-group-ingress \
    --group-id $EC2_SECURITY_GROUP_ID \
    --protocol -1 \
    --port -1 \
    --cidr 0.0.0.0/0 \
    --region $REGION


aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SECURITY_GROUP_ID \
    --protocol -1 \
    --port -1 \
    --cidr $CIDR \
    --region $REGION


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
SUBNET_IDS=( $DATA_TIER_A $DATA_TIER_B)

echo "$SUBNET_ID"

# Enable DNS support
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames



if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME"  --region "$REGION" >/dev/null 2>&1; then
echo "Creating DB subnet group: $DB_SUBNET_GROUP_NAME"
aws rds create-db-subnet-group \
    --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
    --db-subnet-group-description "Rohisubs" \
    --subnet-ids "${SUBNET_IDS[@]}" \
    --region "$REGION" \
    --query "DBSubnetGroup.DBSubnetGroupName" \
    --output text
echo "Createed DB subnetgroup: $DB_SUBNET_GROUP_NAME"
else 
echo "Db subnet group $DB_SUBNET_GROUP_NAME already exists"
fi
echo "Createed DB subnetgroup: $DB_SUBNET_GROUP_NAME"


#########################Creating_RDS#######################################################

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
  --tags "Key=name,Value=${RDS_NAME}"

################Waiting for the rds to come up#############################33

echo "Waiting for Db to become avilable"
aws rds wait db-instance-available --db-instance-identifier "$RDS_NAME" --region "$REGION"

###=================Get the RDs endpoint########################

DB_ENDPOINT=$( aws rds describe-db-instances --db-instance-identifier "$RDS_NAME" --region "$REGION"  --query "DBInstances[0].Endpoint.Address"  --output text )

echo "RDS Instance ready at endpoint: $DB_ENDPOINT"


##===Creating the USer_Data===========

##=== Creating the User Data (with DB injected) ===========

cat > user_data.sh <<'EOF'
#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s) 2>&1

echo "[user-data] Starting bootstrap at $(date --iso-8601=seconds)"

if ! command -v dnf >/dev/null 2>&1; then
  echo "[user-data] dnf not found; this script expects Amazon Linux 2023" >&2
  exit 1
fi

dnf -y update
dnf -y install httpd php php-cli php-mysqlnd

systemctl enable --now httpd

cat <<'PHPINFO' >/var/www/html/info.php
<?php
phpinfo();
PHPINFO

cat <<'PHPAPP' >/var/www/html/index.php
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>🌟 Welcome to My Dynamic AWS Site 🌟</title>
  <style>
    body { margin:0; font-family:'Segoe UI',sans-serif; background:linear-gradient(135deg,#74ABE2,#5563DE); color:white; text-align:center; }
    header { padding:40px; background:rgba(0,0,0,0.5); }
    h1 { font-size:3em; margin:0; }
    p { font-size:1.2em; }
    .card { background:white; color:#333; margin:40px auto; padding:20px; border-radius:12px; max-width:600px; box-shadow:0px 4px 20px rgba(0,0,0,0.3); }
    img { max-width:100%; border-radius:12px; }
    footer { padding:20px; background:rgba(0,0,0,0.4); margin-top:40px; }
  </style>
</head>
<body>
  <header>
    <h1>🌐 My AWS Dynamic Website</h1>
    <p>Running on EC2 + RDS</p>
  </header>
  <div class="card">
    <img src="https://source.unsplash.com/800x400/?nature,technology" alt="Banner Image">
    <h2>Hello from EC2!</h2>
    <p>
      <?php
        mysqli_report(MYSQLI_REPORT_OFF);
        $servername = PHP_DB_HOST;
        $username   = PHP_DB_USER;
        $password   = PHP_DB_PASS;
        $dbname     = PHP_DB_NAME;

        $conn = @mysqli_connect($servername, $username, $password, $dbname);
        if (!$conn) {
          echo '❌ Database connection failed: ' . htmlspecialchars(mysqli_connect_error(), ENT_QUOTES, 'UTF-8');
        } else {
          echo '✅ Connected to database: ' . htmlspecialchars($dbname, ENT_QUOTES, 'UTF-8') . '<br>';
          $result = mysqli_query($conn, 'SELECT NOW() AS nowtime');
          if ($result) {
            $row = mysqli_fetch_assoc($result);
            if ($row && isset($row['nowtime'])) {
              echo '⏰ Current DB time: ' . htmlspecialchars($row['nowtime'], ENT_QUOTES, 'UTF-8');
            }
            mysqli_free_result($result);
          }
          mysqli_close($conn);
        }
      ?>
    </p>
  </div>
  <footer>
    <p>🚀 Powered by AWS | EC2 + RDS + Apache + PHP</p>
  </footer>
</body>
</html>
PHPAPP

cat <<'ENVFILE' >/etc/profile.d/app-env.sh
export DB_HOST=DB_HOST_ENV
export DB_USER=DB_USER_ENV
export DB_PASS=DB_PASS_ENV
export DB_NAME=DB_NAME_ENV
ENVFILE

chown apache:apache /var/www/html/index.php /var/www/html/info.php
chmod 644 /var/www/html/*.php

systemctl restart httpd

curl -fsS http://127.0.0.1/ | head -n 20 || true
curl -fsS http://127.0.0.1/info.php | head -n 20 || true
systemctl status httpd --no-pager || true

echo "[user-data] Completed at $(date --iso-8601=seconds)"
EOF

export DB_ENDPOINT DB_NAME DB_USERNAME DB_PASSWORD
python3 - <<'PY'
import json
import os
from pathlib import Path
import shlex

values = {
    'PHP_DB_HOST': json.dumps(os.environ['DB_ENDPOINT']),
    'PHP_DB_NAME': json.dumps(os.environ['DB_NAME']),
    'PHP_DB_USER': json.dumps(os.environ['DB_USERNAME']),
    'PHP_DB_PASS': json.dumps(os.environ['DB_PASSWORD']),
    'DB_HOST_ENV': shlex.quote(os.environ['DB_ENDPOINT']),
    'DB_NAME_ENV': shlex.quote(os.environ['DB_NAME']),
    'DB_USER_ENV': shlex.quote(os.environ['DB_USERNAME']),
    'DB_PASS_ENV': shlex.quote(os.environ['DB_PASSWORD']),
}

path = Path('user_data.sh')
text = path.read_text()
for placeholder, value in values.items():
    text = text.replace(placeholder, value)
path.write_text(text)
PY



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