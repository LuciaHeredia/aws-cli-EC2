#!/bin/bash
source config.conf # private variables file

######################## Variables ########################
REGION=$REGION
UBUNTU_AMI_ID=$UBUNTU_AMI_ID
RANDOM_STR=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 10)
SG_NAME="aws6-sg-$RANDOM_STR"
USER_DATA_FILE_NAME=$USER_DATA_FILE_NAME
EC2_KEY_PAIR_NAME=$EC2_KEY_PAIR_NAME

######################## 1. VPC ########################
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
        --region "$REGION" --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=VPC-example}]" \
        --query 'Vpc.VpcId' --output text)

echo "Enable DNS resolution..."
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
echo "Enable DNS hostnames..."
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

echo "waiting 10 seconds.."
sleep 10
######################## 2. Subnets ########################
# later we'll declare the first subnet public.
echo "Creating Subnets (public, private)..."
SUBNET_ID_1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=public-subnet}]" \
            --query 'Subnet.SubnetId' --output text)
SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.0.0/24 \
            --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=private-subnet}]" \
            --query 'Subnet.SubnetId' --output text)

echo "waiting 10 seconds.."
sleep 10
######################## 3. Internet Gateway ########################
# used by the private subnet to access the internet for its updates and other packages installations.
echo "Creating Internet Gateway..."
IG_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=ig-example}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)

echo "waiting 10 seconds.."
sleep 10

echo "Attaching IG to the created VPC..."
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IG_ID"

######################## 4. Route Table ########################
echo "Creating Route Table..."
RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=rt-example}]" \
        --query 'RouteTable.RouteTableId' --output text)

echo "waiting 10 seconds.."
sleep 10

echo "Assign the route to this route table..."
aws ec2 create-route --route-table-id "$RT_ID" \
              --destination-cidr-block 0.0.0.0/0 --gateway-id "$IG_ID"

echo "Viewing if Route Table and Subnets created and assigned successfully..."
aws ec2 describe-route-tables --route-table-id "$RT_ID"
aws ec2 describe-subnets --filters "Name=vpc-id,Values="$VPC_ID"" \
                         --query "Subnets[*].{ID:SubnetId,CIDR:CidrBlock}"

######################## 4. Route Table and Public Subnet ########################
echo "Associating Route Table with Public Subnet..."
aws ec2 associate-route-table --subnet-id "$SUBNET_ID_1" --route-table-id "$RT_ID"
echo "Mapping the Public IP to the Public Subnet..."
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID_1" --map-public-ip-on-launch

######################## 5. Key Pair ########################
# if you dont have a key par, create one here and save, then put it in the EC2 Dashboard -> Key Pair, with the same name("AWS-Keypair").
# must be kept safe & secure with the user so that the person can access the EC2 instance created using this key pair.
: <<'COMMENT'
echo "Creating Key Pair..."
EC2_KEY_PAIR_NAME="AWS-Keypair"
aws ec2 create-key-pair --key-name $EC2_KEY_PAIR_NAME \
                        --query "KeyMaterial" --output text > "AWS_Keypair.pem")

# echo "waiting 10 seconds.."
# sleep 10
COMMENT
######################## 6. Security Group ########################
# Allow inbound traffic on port 80(HTTP) and secure connection on port 22(SSH).

echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" --vpc-id "$VPC_ID"\
	--description "SG for EC2 instance with inbound HTTP traffic" \
    --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
	                                    --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
                                        --protocol tcp --port 22 --cidr 0.0.0.0/0

echo "waiting 30 seconds.."
sleep 30
######################## 7. EC2 Instances ########################
# Associate SG with the instance. 
# Install & configure Apache on instance. 

echo "Launching EC2 instances..."
aws ec2 run-instances --region "$REGION" --image-id "$UBUNTU_AMI_ID" --count 1 --instance-type t2.micro \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=i-example}]" \
	--security-group-id "$SG_ID" --subnet-id "$SUBNET_ID_1" \
	--user-data file://"$USER_DATA_FILE_NAME" \
	--key-name "$EC2_KEY_PAIR_NAME"

echo "Deployment complete"
