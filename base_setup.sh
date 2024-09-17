#!/bin/bash

# CLI Script to orchestrate the spin up of lots of resources for an uber-full stack demo.

Base=HomeLink
vnetsnets=2  # Number of subnets to create
vnetsnet1pfxbase="10.0.x.0/24"  # Base prefix for subnets

# List of regions where you want to deploy resources
locations=("UKSouth" "WestEurope" "NorthEurope")
vmresources=("WindowsDc" "linuxserver" "windowsserver")  # Define VM types to deploy
additionalstufftodeploy=("akscluster" "appserviceplan" "appgw" "frontdoor")  # Extra resources to deploy
globalpeeringenabled=true  # Enable global VNet peering

# VM-specific variables
adminUsername="azureuser"
windowsAdminPassword=$(openssl rand -base64 16)  # Generate a random password for Windows VMs
echo "Generated Windows Admin Password: $windowsAdminPassword"

# Loop through each location
for loc in "${locations[@]}"; do

    echo "Deploying resources in $loc..."
    
    # Dynamic naming based on location
    rg="${Base}rg-$loc"
    vnet="${Base}vnet-$loc"
    nsg="${Base}nsg-$loc"
    storageAccount="${Base}storage$loc"
    kv="${Base}kv-$loc"
    vmBase="${Base}-vm-$loc"

    # Create resource group
    az group create --location $loc -g $rg

    # Create virtual network
    az network vnet create --resource-group $rg --name $vnet --address-prefix "10.0.0.0/16" --location $loc

    # Loop to create subnets dynamically
    for i in $(seq 1 $vnetsnets); do
        subnetName="${Base}subnet$i-$loc"
        subnetPrefix="${vnetsnet1pfxbase/x/$i}"  # Replace 'x' with the loop index
        az network vnet subnet create --resource-group $rg --vnet-name $vnet --name $subnetName --address-prefix $subnetPrefix
    done

    # Create Network Security Group
    az network nsg create --resource-group $rg --name $nsg --location $loc

    # Create a Storage Account
    az storage account create --name $storageAccount --resource-group $rg --location $loc --sku Standard_LRS --kind StorageV2

    # Create Key Vault
    az keyvault create --name $kv --resource-group $rg

    # Deploy VM resources in each region (Domain controllers and other VMs)
    for vm in "${vmresources[@]}"; do
        vmName="${vmBase}-${vm}"

        if [[ $vm == "WindowsDc" || $vm == "windowsserver" ]]; then
            az vm create --resource-group $rg --name $vmName --location $loc --vnet-name $vnet --subnet "${Base}subnet1-$loc" --nsg $nsg --image Win2019Datacenter --admin-username $adminUsername --admin-password $windowsAdminPassword --no-wait
        elif [[ $vm == "linuxserver" ]]; then
            az vm create --resource-group $rg --name $vmName --location $loc --vnet-name $vnet --subnet "${Base}subnet2-$loc" --nsg $nsg --image UbuntuLTS --admin-username $adminUsername --generate-ssh-keys --no-wait
        fi
    done

    # Deploy additional resources based on the configuration
    for resource in "${additionalstufftodeploy[@]}"; do
        case $resource in
            "akscluster")
                az aks create --resource-group $rg --name $aksCluster --node-count 1 --generate-ssh-keys --location $loc
                ;;
            "appserviceplan")
                az appservice plan create --resource-group $rg --name "${Base}asp-$loc" --location $loc --sku B1 --is-linux
                ;;
            "appgw")
                az network application-gateway create --resource-group $rg --name "${Base}appgw-$loc" --location $loc --sku Standard_v2 --capacity 2 --vnet-name $vnet --subnet "${Base}subnet1-$loc"
                ;;
            "firewall")
                az network firewall create --resource-group $rg --name "${Base}firewall-$loc" --location $loc --vnet-name $vnet --subnet "${Base}firewallSubnet-$loc"
                ;;
            "bastion")
                az network bastion create --name "${Base}bastion-$loc" --public-ip-address "${Base}bastionIP-$loc" --resource-group $rg --vnet-name $vnet --subnet "${Base}bastionsubnet-$loc" --location $loc
                ;;
            "azuresql")
                sqlServerName="${Base}sql-$loc"
                sqlDbName="${Base}db-$loc"
                az sql server create --name $sqlServerName --resource-group $rg --location $loc --admin-user $adminUsername --admin-password $windowsAdminPassword
                az sql db create --resource-group $rg --server $sqlServerName --name $sqlDbName --service-objective S0
                ;;
            "botservice")
                az bot create --resource-group $rg --name "${Base}bot-$loc" --kind registration --display-name "${Base}BotDisplayName" --endpoint "https://example.com/api/messages"
                ;;
            "acregistry")
                az acr create --resource-group $rg --name $acr --sku Standard --location $loc
                ;;
            "communicationsvc")
                az communication service create --name "${Base}commsvc-$loc" --resource-group $rg --location $loc --data-location $loc
                ;;
        esac
    done

done

# Global VNet Peering (optional)
if [ "$globalpeeringenabled" = true ]; then
    for loc1 in "${locations[@]}"; do
        for loc2 in "${locations[@]}"; do
            if [ "$loc1" != "$loc2" ]; then
                az network vnet peering create --name "${loc1}-to-${loc2}" --resource-group "${Base}rg-$loc1" --vnet-name "${Base}vnet-$loc1" --remote-vnet "${Base}vnet-$loc2" --allow-vnet-access --allow-forwarded-traffic --allow-gateway-transit
            fi
        done
    done
fi

echo "Deployment complete in all locations."
