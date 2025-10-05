#!/bin/bash

source /mnt/c/shellpractice/awscli/variable.sh

set -euo pipefail
exec > >(sudo tee /var/log/user-data.log | logger -t user-data -s) 2>&1




#1 Pick the name for the for BUCKET (must be globally unique as the s3 is global) and REGION with whatever needed:

if  [[ "$REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION \
          >/dev/null
else
        aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION \
        --create-bucket-configuration LocationConstraint=$REGION \
          >/dev/null
fi

## > /dev/null is used to suppress the output of the command. 

echo "S3 Bucket $BUCKET_NAME created successfully in region $REGION"

##2> Uploading the data to the specific s3 bucket
aws s3 cp userdataraw.sh "s3://$BUCKET_NAME/userdataraw.sh"

#6> Making the bucket publically acessabble and the security sucksss.....

aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false


aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowPublicRead",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::'"$BUCKET_NAME"'/*"
            }
        ]
    }'




###3> Making the bucket public
#aws s3api put-object-acl \
#    --bucket $BUCKET_NAME \
#    --key userdataraw.sh \
#    --acl public-read

##4> Getting the HTTPS link for the uploaded file
PUBLIC_URL="https://$BUCKET_NAME.s3.$REGION.amazonaws.com/userdataraw.sh"
echo "Public URL of the uploaded file: $PUBLIC_URL"

