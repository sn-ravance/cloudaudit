##########################################
# Azure Subscription Resource Count
#
# Prerequisites: None
#
# Azure APIs Used:
#
# - az account list
# - az resource list
# - az vm list
#
# Instructions:
#
# - Go to Azure Portal
# - Use Cloud Shell (Bash)
# - Upload the script
# - Run the script:
#       python3 azcount.py
##########################################

import subprocess
import json

# (This script queries for running VMs separately.)

resource_mapping = {
    'Microsoft.Web/sites'                       : 'Function Apps'
}

global_az_resource_count = 0
error_list = []

az_account_list = json.loads(subprocess.getoutput('az account list --all --output json 2>&1'))

global_az_account_census = {}
global_az_account_census['Virtual Machines'] = 0
global_az_account_census['AKS nodes'] = 0
global_az_account_census['Function Apps'] = 0
global_az_account_census['App Service'] = 0
global_az_account_census['Serverless'] = 0

for az_account in az_account_list:
    if az_account['state'] != 'Enabled':
        continue
    print('###################################################################################')
    print("Processing Subscription: {} ({})".format(az_account['name'], az_account['id']))

    az_account_resource_count = 0
    az_account_census = {}
    az_account_census['Virtual Machines'] = 0
    az_account_census['AKS nodes'] = 0
    az_account_census['Function Apps'] = 0
    az_account_census['App Service'] = 0
    az_account_census['Serverless'] = 0

    try:
        vm_list = subprocess.getoutput("az vm list -d  --subscription {} --output json 2>&1 | jq '.[].id'".format(az_account['id']))
        vm_list = vm_list.replace('"', '')
        vm_list = vm_list.split('\n')
        if vm_list != ['']:
            az_account_census['Virtual Machines'] += len(vm_list)
            global_az_account_census['Virtual Machines'] += len(vm_list)

    except Exception as e:
        this_error = "{} ({}) - Error executing 'az vm list'.".format(az_account['name'], az_account['id'])
        error_list.append(this_error)
        print(this_error)
 
     # Checking for AKS node counts (traverse each AKS, and each of its nodepools)
    try:
        az_aks_list = subprocess.getoutput("az aks list --subscription {} --output json 2>&1".format(az_account['id']))
        az_aks_list = json.loads(az_aks_list)
        for aks in az_aks_list:
            az_aks_nodepool_list = subprocess.getoutput("az aks nodepool list --cluster-name {} --resource-group {} --subscription {} --output json 2>&1".format(aks['name'], aks['resourceGroup'], az_account['id']))
            az_aks_nodepool_list = json.loads(az_aks_nodepool_list) 
            for nodepool in az_aks_nodepool_list:
                az_account_census['AKS nodes'] += nodepool['count']
                global_az_account_census['AKS nodes'] += nodepool['count']

    except Exception as e:
        this_error = "{} ({}) - Error executing 'az aks list'.".format(az_account['name'], az_account['id'])
        error_list.append(this_error)
        print(this_error)

    try:
        az_resource_list = subprocess.getoutput("az resource list --subscription {} --output json 2>&1".format(az_account['id']))
        az_resources = json.loads(az_resource_list)
        for az_resource in az_resources:

            resource_type = az_resource['type']
            resource_kind = str(az_resource['kind'])
            resource_name = str(az_resource['name'])
            if (resource_type == "Microsoft.Web/sites" and resource_kind.startswith("functionapp")):
                az_account_census['Function Apps'] += 1
                az_account_census['Serverless'] += 1
                global_az_account_census['Function Apps'] += 1
                global_az_account_census['Serverless'] += 1
                az_account_resource_count += 1
            elif (resource_type == "Microsoft.Web/sites" and not resource_kind.startswith("functionapp")):
                az_account_census['App Service'] += 1
                az_account_census['Serverless'] += 1
                global_az_account_census['App Service'] += 1
                global_az_account_census['Serverless'] += 1
                az_account_resource_count += 1

        for resource_type, resource_count in sorted(az_account_census.items()):
            print("{}: {}".format(resource_type, resource_count))

    except Exception as e:
        this_error = "{} ({}) - Error executing 'az resource list'.".format(az_account['name'], az_account['id'])
        error_list.append(this_error)
        print(this_error)

    print('###################################################################################')
    global_az_resource_count += az_account_resource_count

print()
print('###################################################################################')
print("Total resources across all accounts ({} accounts):".format(len(az_account_list   )))
print("   Virtual Machines: {}".format(global_az_account_census['Virtual Machines']))
print("   Container Hosts (AKS): {}".format(global_az_account_census['AKS nodes']))
print("   Serverless: {}".format(global_az_account_census['Serverless']))
print("      Function Apps: {}".format(global_az_account_census['Function Apps']))
print("      App Service: {}".format(global_az_account_census['App Service']))
print('###################################################################################')
print()

if error_list:
    print('###################################################################################')
    print('Errors:')
    for this_error in error_list:
        print(this_error)
    print('###################################################################################')
    print()

