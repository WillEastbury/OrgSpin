#!/bin/bash
az account show
# az login
# Load the configuration
CONFIG_FILE="config.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq to parse JSON."
    exit 1
fi

locations=$(jq -r '.locations[]' "$CONFIG_FILE")
# Loop through each location
for loc in $locations; do
    echo "Deploying resources in $loc..."

    # Define dynamic names
    rg="${Base}rg-$loc"
    vnet_name=$(jq -r --arg region "$loc" '.resources.vnets.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' "$CONFIG_FILE")
    storage_account=$(jq -r --arg region "$loc" '.resources.storage_accounts.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' "$CONFIG_FILE")
    kv_name=$(jq -r --arg region "$loc" '.resources.key_vaults.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' "$CONFIG_FILE")

    # Create resource group
    az group create --location $loc -g $rg

    # Create virtual network
    az network vnet create --resource-group $rg --name $vnet_name --address-prefix "10.0.0.0/16" --location $loc

    # Create subnets
    subnets=$(jq -c '.resources.vnets.subnets[]' "$CONFIG_FILE")
    for subnet in $subnets; do
        subnet_name=$(jq -r --arg region "$loc" '.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' <<< "$subnet")
        subnet_prefix=$(jq -r '.address_prefix' <<< "$subnet")
        az network vnet subnet create --resource-group $rg --vnet-name $vnet_name --name $subnet_name --address-prefix $subnet_prefix
    done

    # Create Storage Account
    az storage account create --name $storage_account --resource-group $rg --location $loc --sku Standard_LRS --kind StorageV2

    # Create Key Vault
    az keyvault create --name $kv_name --resource-group $rg --location $loc

    # Create other resources as defined in the config
    # Example: Create VM
    vm_name=$(jq -r --arg region "$loc" '.resources.vm_windows_dc.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' "$CONFIG_FILE")
    admin_username=$(jq -r '.resources.vm_windows_dc.admin_username' "$CONFIG_FILE")
    admin_password=$(jq -r '.resources.vm_windows_dc.admin_password' "$CONFIG_FILE")
    az vm create --resource-group $rg --name $vm_name --location $loc --vnet-name $vnet_name --subnet "${Base}subnet1-$loc" --image Win2019Datacenter --admin-username $admin_username --admin-password $admin_password

    # Example: Create Application Gateway
    appgw_name=$(jq -r --arg region "$loc" '.resources.app_gateways.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' "$CONFIG_FILE")
    az network application-gateway create --resource-group $rg --name $appgw_name --location $loc --sku Standard_v2 --capacity 2 --vnet-name $vnet_name --subnet "${Base}subnet1-$loc"

    # Example: Create Firewall
    firewall_name=$(jq -r --arg region "$loc" '.resources.firewalls.name | sub("{prefix}"; $Base) | sub("{region}"; $region)' "$CONFIG_FILE")
    az network firewall create --resource-group $rg --name $firewall_name --location $loc --vnet-name $vnet_name --subnet "${Base}firewallSubnet-$loc"

    echo "Deployment complete in $loc."
done