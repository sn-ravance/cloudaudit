#!/bin/bash

##########################################################################################
# Instructions:
#
# - Make this script executable:
#   chmod +x awscount.sh
#
# - Run this script:
#   sizing-script-aws.sh
#   sizing-script-aws.sh org (see below)
#
# API/CLI used:
#
# - aws organizations describe-organization (optional)
# - aws organizations list-accounts (optional)
# - aws sts assume-role (optional)
# - aws lambda list-functions
# - aws ec2 describe-instances
# - aws ecs aws ecs list-clusters
# - aws ecs aws ecs list-tasks
# - aws ecs aws ecs describe-tasks
##########################################################################################

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Optionally query the AWS Organization by passing "org" as an argument.
##########################################################################################

if [ "${1}X" == "orgX" ]; then
   USE_AWS_ORG="true"
else
   USE_AWS_ORG="false"
fi

##########################################################################################
## Optionally pass an AWS profile to use. Profiles are available at ~/.aws/config (Linux & Mac) or %USERPROFILE%\.aws\config (Windows)
##########################################################################################

echo ">>> Profiles are available at ~/.aws/config (Linux & Mac) or %USERPROFILE%\.aws\config (Windows)"

ORIGINAL_AWS_PROFILE_ENV=$(printenv AWS_PROFILE)
echo "Setting AWS_PROFILE environment variable for this run"
echo ""

echo "Available profiles:"
INSTALLED_PROFILES=$(aws configure list-profiles)
echo "$INSTALLED_PROFILES"
echo ""


INSTALLED_PROFILES_COUNT=$(aws configure list-profiles | wc -l)

if [ ${INSTALLED_PROFILES_COUNT} -eq 1 ]; then
  echo ""
  echo ">>> Only one profile available. Running with it."
  export AWS_PROFILE=${INSTALLED_PROFILES}
else
  echo ">>> Please enter the desired AWS configuration profile to use."
  read AWS_PROFILE_INPUT
  while [[ $AWS_PROFILE_INPUT = "" ]]; do
    echo "AWS Configuration profile cannot be empty"
    read AWS_PROFILE_INPUT
  done
  export AWS_PROFILE=${AWS_PROFILE_INPUT}
fi

##########################################################################################
## Utility functions.
##########################################################################################

error_and_exit() {
  echo
  echo "ERROR: ${1}"
  echo
  exit 1
}

##########################################################################################
## AWS Utility functions.
##########################################################################################

aws_ec2_describe_regions() {
  RESULT=$(aws ec2 describe-regions --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

aws_organizations_describe_organization() {
  RESULT=$(aws organizations describe-organization --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

aws_organizations_list_accounts() {
  RESULT=$(aws organizations list-accounts --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

aws_sts_assume_role() {
  RESULT=$(aws sts assume-role --region us-east-1 --role-arn="${1}" --role-session-name=sizing-resources --duration-seconds=999 --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

####

aws_ec2_describe_instances() {
  RESULT=$(aws ec2 describe-instances --region="${1}" --query 'Reservations[*].Instances[*].{Instance:InstanceId}' --filters "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" --output json | grep Instance | awk '{print $2}' | sed 's/"//g' | wc -l 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_list_eks_nodes() {
  CLUSTERS=$(aws eks list-clusters --region="${1}" --output json | jq -r '.clusters[]' 2>/dev/null)
  XIFS=$IFS
  IFS=$'\n' CLUSTERS=($CLUSTERS)
  IFS=$XIFS
  RESULT=0
  for i in "${CLUSTERS[@]}"
  do
    NODES=$(aws ec2 describe-instances --region="${1}" --filters Name=tag-key,Values=kubernetes.io/cluster/${i} Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped | jq -r '.Reservations[] | .Instances[] | .InstanceId' | wc -l 2>/dev/null)
    if [ ${#NODES[@]} -eq 0 ]; then
      RESULT=$(($RESULT + 0))
    else
      RESULT=$(($RESULT + $NODES))
    fi
  done

  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_list_functions() {
  RESULT=$(aws lambda list-functions --region="${1}" --query 'Functions[*].{Function:FunctionArn}' --output json | grep Function | awk '{print $2}' | sed 's/"//g' | wc -l 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_list_ecs_containers() {
  CLUSTERS=$(aws ecs list-clusters --region="${1}" --output json | jq -r '.clusterArns[]' 2>/dev/null)
  XIFS=$IFS
  IFS=$'\n' CLUSTERS=($CLUSTERS)
  IFS=$XIFS
  RESULT=0
  for i in "${CLUSTERS[@]}"
  do
    TASKS=$(aws ecs list-tasks --region="${1}" --cluster "${i}" --output json | jq -r '.taskArns[]' 2>/dev/null)
    XIFS=$IFS
    IFS=$'\n' TASKS=($TASKS)
    IFS=$XIFS
    for j in "${TASKS[@]}"
    do
      CONTAINERS=$(aws ecs describe-tasks --region="${1}" --cluster "${i}" --tasks "${j}" --output json | jq -r '.tasks[] | .containers[] | .containerArn' | wc -l 2>/dev/null)
      if [ ${#CONTAINERS[@]} -eq 0 ]; then
        RESULT=$(($RESULT + 0))
      else
        RESULT=$(($RESULT + $CONTAINERS))
      fi
    done
  done

  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}


####

get_region_list() {
  echo "###################################################################################"
  echo "Querying AWS Regions"

  REGIONS=$(aws_ec2_describe_regions | jq -r '.Regions[] | .RegionName' 2>/dev/null | sort)

  XIFS=$IFS
  IFS=$'\n' REGION_LIST=($REGIONS)
  IFS=$XIFS

  if [ ${#REGION_LIST[@]} -eq 0 ]; then
    echo "  Warning: Using default region list"
    REGION_LIST=(us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 eu-north-1 eu-central-1 eu-west-1 sa-east-1 eu-west-2 eu-west-3 ca-central-1)
  fi

  echo "  Total number of regions: ${#REGION_LIST[@]}"
  echo "###################################################################################"
  echo ""
}

get_account_list() {
  if [ "${USE_AWS_ORG}" = "true" ]; then
    echo "###################################################################################"
    echo "Querying AWS Organization"
    MASTER_ACCOUNT_ID=$(aws_organizations_describe_organization | jq -r '.Organization.MasterAccountId' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "${MASTER_ACCOUNT_ID}" ]; then
      error_and_exit "Error: Failed to describe AWS Organization, check aws cli setup, and access to the AWS Organizations API."
    fi
    ACCOUNT_LIST=$(aws_organizations_list_accounts)
    if [ $? -ne 0 ] || [ -z "${ACCOUNT_LIST}" ]; then
      error_and_exit "Error: Failed to list AWS Organization accounts, check aws cli setup, and access to the AWS Organizations API."
    fi
    TOTAL_ACCOUNTS=$(echo "${ACCOUNT_LIST}" | jq '.Accounts | length' 2>/dev/null)
    echo "  Total number of member accounts: ${TOTAL_ACCOUNTS}"
    echo "###################################################################################"
    echo ""
  else
    MASTER_ACCOUNT_ID=""
    ACCOUNT_LIST=""
    TOTAL_ACCOUNTS=1
  fi
}

assume_role() {
  ACCOUNT_NAME="${1}"
  ACCOUNT_ID="${2}"
  echo "###################################################################################"
  echo "Processing Account: ${ACCOUNT_NAME} (${ACCOUNT_ID})"
  if [[ 10#$ACCOUNT_ID -eq 10#$MASTER_ACCOUNT_ID ]]; then 
    echo "  Account is the master account, skipping assume role ..."
  else
    ACCOUNT_ASSUME_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole"
    SESSION_JSON=$(aws_sts_assume_role "${ACCOUNT_ASSUME_ROLE_ARN}")
    if [ $? -ne 0 ] || [ -z "${SESSION_JSON}" ]; then
      ASSUME_ROLE_ERROR="true"
      echo "  Warning: Failed to assume role into Member Account ${ACCOUNT_NAME} (${ACCOUNT_ID}), skipping ..."
    else
      # Export environment variables used to connect to this member account.
      AWS_ACCESS_KEY_ID=$(echo "${SESSION_JSON}"     | jq .Credentials.AccessKeyId     2>/dev/null | sed -e 's/^"//' -e 's/"$//')
      AWS_SECRET_ACCESS_KEY=$(echo "${SESSION_JSON}" | jq .Credentials.SecretAccessKey 2>/dev/null | sed -e 's/^"//' -e 's/"$//')
      AWS_SESSION_TOKEN=$(echo "${SESSION_JSON}"     | jq .Credentials.SessionToken    2>/dev/null | sed -e 's/^"//' -e 's/"$//')
      export AWS_ACCESS_KEY_ID
      export AWS_SECRET_ACCESS_KEY
      export AWS_SESSION_TOKEN
    fi
  fi
  echo "###################################################################################"
  echo ""
}

##########################################################################################
# Unset environment variables used to assume role into the last member account.
##########################################################################################

unassume_role() {
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
}
      
##########################################################################################
## Set or reset counters.
##########################################################################################

reset_account_counters() {
  EC2_INSTANCE_COUNT=0
  EC2_INSTANCE_EKS_COUNT=0
  LAMBDA_FUNCTIONS_COUNT=0
  ECS_CONTAINER_COUNT=0
  WORKLOAD_COUNT=0
}

reset_global_counters() {
  EC2_INSTANCE_COUNT_GLOBAL=0
  EC2_INSTANCE_EKS_COUNT_GLOBAL=0
  LAMBDA_FUNCTIONS_COUNT_GLOBAL=0
  ECS_CONTAINER_COUNT_GLOBAL=0
  SERVERLESS_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL_LICENSED=0
}

##########################################################################################
## Iterate through the (or each member) account, region, and billable resource type.
##########################################################################################

count_account_resources() {
  for ((ACCOUNT_INDEX=0; ACCOUNT_INDEX<=(TOTAL_ACCOUNTS-1); ACCOUNT_INDEX++))
  do
    if [ "${USE_AWS_ORG}" = "true" ]; then
      ACCOUNT_NAME=$(echo "${ACCOUNT_LIST}" | jq -r .Accounts[$ACCOUNT_INDEX].Name 2>/dev/null)
      ACCOUNT_ID=$(echo "${ACCOUNT_LIST}"   | jq -r .Accounts[$ACCOUNT_INDEX].Id   2>/dev/null)
      ASSUME_ROLE_ERROR=""
      assume_role "${ACCOUNT_NAME}" "${ACCOUNT_ID}"
      if [ -n "${ASSUME_ROLE_ERROR}" ]; then
        continue
      fi
    fi

    echo "###################################################################################"
    echo "Counting the existing EC2 Instances"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_ec2_describe_instances "${i}" 2>/dev/null)
      echo "  Count of existing EC2 Instances in Region ${i}: ${RESOURCE_COUNT}"
      EC2_INSTANCE_COUNT=$(($EC2_INSTANCE_COUNT + $RESOURCE_COUNT))
    done
    echo "Total EC2 Instances across all regions: ${EC2_INSTANCE_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "Counting the existing EKS-owned EC2 Instances"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_list_eks_nodes "${i}" 2>/dev/null)
      echo "  Count of existing EKS-owned EC2 Instances in Region ${i}: ${RESOURCE_COUNT}"
      EC2_INSTANCE_EKS_COUNT=$(($EC2_INSTANCE_EKS_COUNT + $RESOURCE_COUNT))
    done
    echo "Total EKS-owned EC2 Instances across all regions: ${EC2_INSTANCE_EKS_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "Counting the number of Lambda Functions"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_list_functions "${i}" 2>/dev/null)
      echo "  Count of existing Lambda Functions in Region ${i}: ${RESOURCE_COUNT}"
      LAMBDA_FUNCTIONS_COUNT=$(($LAMBDA_FUNCTIONS_COUNT + $RESOURCE_COUNT))
    done
    echo "Total number of Lambda Functions across all regions: ${LAMBDA_FUNCTIONS_COUNT}"
    echo "###################################################################################"
    echo ""

    echo "###################################################################################"
    echo "Counting the existing ECS Containers"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT=$(aws_list_ecs_containers "${i}" 2>/dev/null)
      echo "  Count of existing ECS Containers in Region ${i}: ${RESOURCE_COUNT}"
      ECS_CONTAINER_COUNT=$(($ECS_CONTAINER_COUNT + $RESOURCE_COUNT))
    done
    echo "Total ECS Containers across all regions: ${ECS_CONTAINER_COUNT}"
    echo "###################################################################################"
    echo ""

    if [ "${USE_AWS_ORG}" = "true" ]; then
      WORKLOAD_COUNT=$(($EC2_INSTANCE_COUNT + $LAMBDA_FUNCTIONS_COUNT + $ECS_CONTAINER_COUNT))
      echo "###################################################################################"
      echo "Member Account Totals"
      echo "Total billable resources for Member Account ${ACCOUNT_NAME} ($ACCOUNT_ID): ${WORKLOAD_COUNT}"
      echo "###################################################################################"
      echo ""
    fi

    EC2_INSTANCE_EKS_COUNT_GLOBAL=$(($EC2_INSTANCE_EKS_COUNT_GLOBAL + $EC2_INSTANCE_EKS_COUNT))
    EC2_INSTANCE_COUNT_GLOBAL=$(($EC2_INSTANCE_COUNT_GLOBAL + $EC2_INSTANCE_COUNT))
    LAMBDA_FUNCTIONS_COUNT_GLOBAL=$(($LAMBDA_FUNCTIONS_COUNT_GLOBAL + $LAMBDA_FUNCTIONS_COUNT))
    ECS_CONTAINER_COUNT_GLOBAL=$(($ECS_CONTAINER_COUNT_GLOBAL + $ECS_CONTAINER_COUNT))
    SERVERLESS_COUNT_GLOBAL=$(($ECS_CONTAINER_COUNT_GLOBAL + $LAMBDA_FUNCTIONS_COUNT_GLOBAL))

    reset_account_counters

    if [ "${USE_AWS_ORG}" = "true" ]; then
      unassume_role
    fi
  done

  WORKLOAD_COUNT_GLOBAL=$(($EC2_INSTANCE_COUNT_GLOBAL + $EC2_INSTANCE_EKS_COUNT_GLOBAL + $LAMBDA_FUNCTIONS_COUNT_GLOBAL + $ECS_CONTAINER_COUNT_GLOBAL))

  echo "###################################################################################"
  echo "Totals accross all regions"
  echo "  Virtual Machines (EC2 Instances): ${EC2_INSTANCE_COUNT_GLOBAL}"
  echo "  Container Hosts (EKS): ${EC2_INSTANCE_EKS_COUNT_GLOBAL}"
  echo "  Serverless: ${SERVERLESS_COUNT_GLOBAL}"
  echo "    Lambda Functions: ${LAMBDA_FUNCTIONS_COUNT_GLOBAL}"
  echo "    ECS Containers: ${ECS_CONTAINER_COUNT_GLOBAL}"
  echo "###################################################################################"
}

##########################################################################################
# Allow shellspec to source this script.
##########################################################################################

${__SOURCED__:+return}

##########################################################################################
# Main.
##########################################################################################

get_account_list
get_region_list
reset_account_counters
reset_global_counters
count_account_resources

export AWS_PROFILE=${ORIGINAL_AWS_PROFILE_ENV}