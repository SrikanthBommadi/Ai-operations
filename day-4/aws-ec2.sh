#!/bin/bash

# script name: aws-ec2.sh
# description: Launch or destroy AWS EC2 resources.

REGION="us-east-1"
INSTANCE_TYPE="t2.micro"
AMI_ID="ami-09c813fb71547fc4f"
SECURITY_GROUP_NAME="my-security-group"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.0.0/24"

STATE_FILE="aws-ec2.state"

if [[ "$1" == "destroy" ]]; then
    # Read resource IDs from state file
    if [[ -f $STATE_FILE ]]; then
        source $STATE_FILE
        if [[ -z "$INSTANCE_ID" || -z "$SECURITY_GROUP_ID" || -z "$SUBNET_ID" || -z "$VPC_ID" ]]; then
            echo "Error: Missing resource IDs in state file."
            exit 1
        fi

        echo "Terminating EC2 Instance: $INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION

        echo "Waiting for EC2 Instance to terminate..."
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION

        echo "Deleting Security Group: $SECURITY_GROUP_ID"
        aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID --region $REGION

        echo "Deleting Subnet: $SUBNET_ID"
        aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $REGION

        echo "Deleting VPC: $VPC_ID"
        aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION

        rm -f $STATE_FILE
        echo "Resources destroyed."
    else
        echo "No state file found. Nothing to destroy."
    fi
    exit 0
fi

# Create resources
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $REGION --query 'Vpc.VpcId' --output text)
echo "Created VPC: $VPC_ID"

SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR --region $REGION --query 'Subnet.SubnetId' --output text)
echo "Created Subnet: $SUBNET_ID"

SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description "My security group" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
echo "Created Security Group: $SECURITY_GROUP_ID"

aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
echo "Authorized inbound SSH (port 22) for Security Group: $SECURITY_GROUP_ID"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --security-group-ids $SECURITY_GROUP_ID \
    --subnet-id $SUBNET_ID \
    --region $REGION \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "Launched EC2 Instance: $INSTANCE_ID"

# Save resource IDs for later destruction
cat > $STATE_FILE <<EOF
VPC_ID=$VPC_ID
SUBNET_ID=$SUBNET_ID
SECURITY_GROUP_ID=$SECURITY_GROUP_ID
INSTANCE_ID=$INSTANCE_ID
EOF