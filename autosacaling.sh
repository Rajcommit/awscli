#!/bin/bash

set -euo pipefail

source /mnt/c/shellpractice/awscli/variable.sh

export AWS_PAGER=""

read -rp "Enter the name of Launch Template (default: ASGLaunchTemplate): " LAUNCH_TEMPLATE
LAUNCH_TEMPLATE=${LAUNCH_TEMPLATE:-ASGLaunchTemplate}

read -rp "Enter AWS region (default: us-east-1): " REGION
REGION=${REGION:-us-east-1}

KEY_PAIR=$(aws ec2 describe-instances --instance-ids "$InstanceId" --region "$REGION" --query 'Reservations[0].Instances[0].KeyName' --output text)
INSTANCE_TYPE=$(aws ec2 describe-instances --instance-ids "$InstanceId" --region "$REGION" --query 'Reservations[0].Instances[0].InstanceType' --output text)
TARGET_GROUP=$(aws elbv2 describe-target-groups --names "$TARGET_GROUP_NAME" --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text)

if [ "$KEY_PAIR" = "None" ]; then
  KEY_PAIR=""
fi

if [ -z "$INSTANCE_TYPE" ] || [ "$INSTANCE_TYPE" = "None" ]; then
  echo "Unable to determine instance type for instance $InstanceId in region $REGION."
  exit 1
fi




##===============================================Create a launch template from an existing instance==============================================












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

#export DB_ENDPOINT DB_NAME DB_USERNAME DB_PASSWORD
export DB_ENDPOINT="rohurds.c49gci4ay5yo.us-east-1.rds.amazonaws.com"
export DB_NAME="databse"
export DB_USERNAME="rohurds"
export DB_PASSWORD="redhatrohini"
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















###================================================================Create Auto Scaling Group===========================================================










#echo "Creating Launch Template: $LAUNCH_TEMPLATE"
#
#aws ec2 create-launch-template \
#  --launch-template-name "$LAUNCH_TEMPLATE" \
#  --version-description "Initial_Version" \
#  --launch-template-data "$(aws ec2 describe-instances --instance-ids "$InstanceId" --region "$REGION" --query 'Reservations[0].Instances[0]' --output json)" \
#  --region "$REGION"
#
#echo "Launch Template $LAUNCH_TEMPLATE created."
#
#LATEST_VERSION=$(aws ec2 create-launch-template-version \
#  --launch-template-name "$LAUNCH_TEMPLATE" \
#  --source-version 1 \
#  --version-description "Associate public IPv4" \
#  --launch-template-data '{
#    "NetworkInterfaces": [
#      {
#        "DeviceIndex": 0,
#        "AssociatePublicIpAddress": true
#      }
#    ]
#  }' \
#  --region "$REGION" \
#  --query 'LaunchTemplateVersion.VersionNumber' \
#  --output text)
#
#echo "Launch Template version $LATEST_VERSION adds public IPv4 association."

echo "Creating Auto Scaling Group: $ASG_NAME"

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateName=$LAUNCH_TEMPLATE,Version=1" \
  --min-size "$MIN_SIZE" \
  --max-size "$MAX_SIZE" \
  --desired-capacity "$DESIRED_CAPACITY" \
  --vpc-zone-identifier "$SUBNET_ID" \
  --target-group-arns "$TARGET_GROUP" \
  --region "$REGION"

aws autoscaling attach-instances \
  --instance-ids "$InstanceId" \
  --auto-scaling-group-name "$ASG_NAME" \
  --region "$REGION"

echo "Auto Scaling Group $ASG_NAME created with desired capacity $DESIRED_CAPACITY"
