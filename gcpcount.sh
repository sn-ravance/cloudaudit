#!/bin/bash

# Instructions:
#
# - Go to the GCP Console
#
# - Open Cloud Shell >_
#
# - Click on three dot vertical menu on the right side (left of minimize button)
#
# - Upload this script
#
# - Make this script executable:
#   chmod +x resource-count-gcp.sh
#
# - Run this script:
#   gcpcount.sh
#   gcpcount.sh verbose (see below)
#
# This script may generate errors when:
#
# - The API is not enabled (and gcloud prompts you to enable the API).
# - You don't have permission to make the API calls.
#
# API/CLI used:
#
# - gcloud projects list
# - gcloud compute instances list
# - gcloud functions list
##########################################################################################

os=$(uname -s)

if [ "$os" = "Darwin" ]; then
  date=$(date -v-1d +%F)
else
  date=$(date -d "yesterday" '+%Y-%m-%d')
fi

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Optionally enable verbose mode by passing "verbose" as an argument.
##########################################################################################

# By default:
#
# - You will not be prompted to enable an API (we assume that you don't use the service, thus resource count is assumed to be 0).
# - When an error is encountered, you most likely don't have API access, thus resource count is assumed to be 0).

if [ "${1}X" == "verboseX" ]; then
  VERBOSITY_ARGS="--verbosity error"
else
  VERBOSITY_ARGS="--verbosity critical --quiet"
fi

##########################################################################################
## GCP Utility functions.
##########################################################################################

gcloud_projects_list() {
  RESULT=$(gcloud projects list --format json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_instances_list() {
  RESULT=$(gcloud compute instances list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_compute_instances_list_gke() {
  RESULT=$(gcloud compute instances list --project "${1}" --filter="labels:goog-gke-node" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

gcloud_functions_list() {
  RESULT=$(gcloud functions list --project "${1}" --format json $VERBOSITY_ARGS 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}
####

get_project_list() {
  PROJECTS=($(gcloud_projects_list | jq  -r '.[].projectId'))
  TOTAL_PROJECTS=${#PROJECTS[@]}
}

##########################################################################################
## Set or reset counters.
##########################################################################################

reset_project_counters() {
  COMPUTE_INSTANCES_COUNT=0
  COMPUTE_INSTANCES_GKE_COUNT=0
  FUNCTIONS_COUNT=0
  WORKLOAD_COUNT=0
}

reset_global_counters() {
  COMPUTE_INSTANCES_COUNT_GLOBAL=0
  COMPUTE_INSTANCES_GKE_COUNT_GLOBAL=0
  FUNCTIONS_COUNT_GLOBAL=0
  WORKLOAD_COUNT_GLOBAL=0
}

##########################################################################################
## Iterate through the projects, and billable resource types.
##########################################################################################

count_project_resources() {
  for ((PROJECT_INDEX=0; PROJECT_INDEX<=(TOTAL_PROJECTS-1); PROJECT_INDEX++))
  do
    PROJECT="${PROJECTS[$PROJECT_INDEX]}"

    echo "###################################################################################"
    echo "Processing Project: ${PROJECT}"

    RESOURCE_COUNT=$(gcloud_compute_instances_list "${PROJECT}" | jq '.[].name' | wc -l)
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT + RESOURCE_COUNT))
    RESOURCE_COUNT=$(gcloud_compute_instances_list_gke "${PROJECT}" | jq '.[].name' | wc -l)
    COMPUTE_INSTANCES_GKE_COUNT=$((COMPUTE_INSTANCES_GKE_COUNT + RESOURCE_COUNT))
    COMPUTE_INSTANCES_COUNT=$((COMPUTE_INSTANCES_COUNT - COMPUTE_INSTANCES_GKE_COUNT))
    echo "   Virtual Machines (Compute Instances): ${COMPUTE_INSTANCES_COUNT}"
    echo "   Container Hosts (GKE): ${COMPUTE_INSTANCES_GKE_COUNT}"
    
    RESOURCE_COUNT=$(gcloud_functions_list "${PROJECT}" | jq '.[].name' | wc -l)
    FUNCTIONS_COUNT=$((FUNCTIONS_COUNT + RESOURCE_COUNT))
    echo "   Cloud Functions: ${FUNCTIONS_COUNT}"

    WORKLOAD_COUNT=$((COMPUTE_INSTANCES_COUNT + FUNCTIONS_COUNT))
    # echo "Total billable resources for Project ${PROJECTS[$PROJECT_INDEX]}: ${WORKLOAD_COUNT}"
    echo "###################################################################################"
    echo ""

    COMPUTE_INSTANCES_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + COMPUTE_INSTANCES_COUNT))
    COMPUTE_INSTANCES_GKE_COUNT_GLOBAL=$((COMPUTE_INSTANCES_GKE_COUNT_GLOBAL + COMPUTE_INSTANCES_GKE_COUNT))
    FUNCTIONS_COUNT_GLOBAL=$((FUNCTIONS_COUNT_GLOBAL + FUNCTIONS_COUNT))
    
    SERVERLESS_COUNT_GLOBAL=$((FUNCTIONS_COUNT_GLOBAL))
    
    reset_project_counters
  done

  echo "###################################################################################"
  echo "Total resources accors all projects:"
  echo "   Virtual Machines: ${COMPUTE_INSTANCES_COUNT_GLOBAL}"
  echo "   Container Hosts (GKE): ${COMPUTE_INSTANCES_GKE_COUNT_GLOBAL}"
  echo "   Serverless: ${SERVERLESS_COUNT_GLOBAL}"
  echo "      Cloud Functions: ${FUNCTIONS_COUNT_GLOBAL}"
  #WORKLOAD_COUNT_GLOBAL=$((COMPUTE_INSTANCES_COUNT_GLOBAL + FUNCTIONS_COUNT_GLOBAL))
  #echo "Total billable resources for all projects: ${WORKLOAD_COUNT_GLOBAL}"
  # echo "------------"
  echo "###################################################################################"
}

##########################################################################################
# Allow shellspec to source this script.
##########################################################################################

${__SOURCED__:+return}

##########################################################################################
# Main.
##########################################################################################

get_project_list
reset_project_counters
reset_global_counters
count_project_resources