#!/bin/bash
set -e
# run like this 
# bash v2.sh willdemo uksouth | tee -a error.log 
# This script creates a resource group and deploys a set of resources to Azure for a basic vnet protected bot that can integrate with Microsoft Teams

if [ $# -eq 0 ]
  then
    echo "No arguments supplied, param 1 should be the base name of the resources, param 2 should be the location"
    exit 1
fi

if [ $# -eq 1 ]
  then
    echo "No location supplied, param 2 should be the location"
    exit 1
fi

basename=$1 
location=$2

echo "Creating resources with basename $basename in location $location"

resourceGroup="${basename}rg"
cosmosDbAccount="${basename}cosmosdb"
cosmosDbDatabase="${basename}db"
openAIName="${basename}oai"
appServicePlan="${basename}appserviceplan"
functionAppPlanName="${basename}functionappplan"

webAppName="${basename}webapp"
functionAppName="${basename}functionapp"
storageAccountName="${basename}storage"
vnetName="${basename}vnet"
addressPrefix="10.0.0.0/16"
# Subnet 1 - app gateway subnet
# subnet 2 - private endpoints
# subnet 3 - vnet integration for app service and function app
subnet1Name="${vnetName}subnet1"
subnet2Name="${vnetName}subnet2"
subnet3Name="${vnetName}subnet3"
subnet1Prefix="10.0.1.0/24"
subnet2Prefix="10.0.2.0/24"
subnet3Prefix="10.0.3.0/24"
appGatewayName="${basename}appgateway"
publicIPName="${basename}publicip"
botServiceName="${basename}botservice"
acsServiceName="${basename}acsservice"

appServicePlanSku="S1"
functionsSku="EP1"
cogServSku="S0"
cogServAcctType="OpenAI"
agsku="Standard_v2"
agcap=1

appId="your-app-id" 
appPassword="your-app-password"

if false; then

    az login

    echo creating rg $resourceGroup
        az group create --name $resourceGroup --location $location

    echo creating vnet $vnetName
        az network vnet create --resource-group $resourceGroup --name $vnetName --address-prefix $addressPrefix --location $location
    
    echo creating subnets
        az network vnet subnet create --resource-group $resourceGroup --vnet-name $vnetName --name $subnet1Name --address-prefix $subnet1Prefix
        az network vnet subnet create --resource-group $resourceGroup --vnet-name $vnetName --name $subnet2Name --address-prefix $subnet2Prefix
        az network vnet subnet create --resource-group $resourceGroup --vnet-name $vnetName --name $subnet3Name --address-prefix $subnet3Prefix --delegations Microsoft.Web/serverFarms

    echo creating public ip for gateway $publicIPName
        az network public-ip create --resource-group $resourceGroup --name $publicIPName --allocation-method Static

    echo creating cognitive services $openAIName
        az cognitiveservices account create --name $openAIName --resource-group $resourceGroup --kind $cogServAcctType --sku $cogServSku --location $location --custom-domain $openAIName --assign-identity
        echo creating storage account $storageAccountName
        az storage account create --name $storageAccountName --resource-group $resourceGroup --location $location --sku Standard_LRS

    echo creating app service $webAppName
        az appservice plan create --name $appServicePlan --resource-group $resourceGroup --location $location --sku $appServicePlanSku
        az webapp create --name $webAppName --resource-group $resourceGroup --plan $appServicePlan
        az webapp vnet-integration add --name $webAppName --resource-group $resourceGroup --vnet $vnetName --subnet $subnet3Name

    echo creating function app $functionAppName
        az functionapp plan create --name $functionAppPlanName --resource-group $resourceGroup --location $location --sku $functionsSku
        az functionapp create --resource-group $resourceGroup --runtime dotnet --name $functionAppName --storage-account $storageAccountName --plan $functionAppPlanName
        az functionapp vnet-integration add --name $functionAppName --resource-group $resourceGroup --vnet $vnetName --subnet $subnet3Name

fi; 

echo creating cosmosdb $cosmosDbAccount
az cosmosdb create --name $cosmosDbAccount --resource-group $resourceGroup --locations regionName=$location
az cosmosdb sql database create --account-name $cosmosDbAccount --resource-group $resourceGroup --name $cosmosDbDatabase
az cosmosdb sql container create --account-name $cosmosDbAccount --resource-group $resourceGroup --database-name $cosmosDbDatabase --name "items" --partition-key-path "/id"

# az bot create --resource-group $resourceGroup --name $botServiceName --sku F0 --location $location --app-type registration --appid $appId
# az bot create --resource-group $resourceGroup --name $botServiceName --sku F0 --appid myAppId --app-type registration --endpoint "https://${webAppName}azurewebsites.net/api/messages"} --kind registration --password password

echo creating private link infrastructure in vnet $vnetName
echo creating private dns zones
az network private-dns zone create --resource-group $resourceGroup --name privatelink.documents.azure.com
az network private-dns zone create --resource-group $resourceGroup --name privatelink.cognitiveservices.azure.com
az network private-dns zone create --resource-group $resourceGroup --name privatelink.azurewebsites.net
echo creating private dns links
az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.documents.azure.com --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.cognitiveservices.azure.com --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false

# BUG Investigate this... Why do I have to strip the \r from the resourceId? I don't have to do this for the other resources
# https://github.com/Azure/azure-cli/issues/21457#issuecomment-1068866984

echo setting up private endpoint for cognitive services $openAIName 
resIdcr=$(az cognitiveservices account show --name $openAIName --resource-group $resourceGroup --query id --output tsv) 
resourceId=${resIdcr//$'\r'}
az resource update --ids $resourceId --set properties.networkAcls="{'defaultAction':'Deny'}"
az network private-endpoint create --resource-group $resourceGroup --name ${basename}cogservprivateendpoint    --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id account --connection-name ${basename}cogservconnection 
ipwithlf=$(az network private-endpoint show --name ${basename}cogservprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv) 
ipwithoutlf=${ipwithlf//$'\r'}
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.cognitiveservices.azure.com --record-set-name $openAIName --ipv4-address $ipwithoutlf

echo setting up private endpoint for cosmosdb  $cosmosDbAccount
resIdcr=$(az cosmosdb show --name $cosmosDbAccount --resource-group $resourceGroup --query id --output tsv)
resourceId=${resIdcr//$'\r'}
az network private-endpoint create --resource-group $resourceGroup --name ${basename}cosmosdbprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id sql --connection-name ${basename}sqlconnection
ipwithlf=$(az network private-endpoint show --name ${basename}cosmosdbprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv) 
ipwithoutlf=${ipwithlf//$'\r'}
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.documents.azure.com --record-set-name $cosmosDbAccount --ipv4-address $ipwithoutlf

echo setting up private endpoint for app service $webAppName
resIdcr=$(az webapp show --name $webAppName --resource-group $resourceGroup --query id --output tsv)
resourceId=${resIdcr//$'\r'}
az network private-endpoint create --resource-group $resourceGroup --name ${basename}webappprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id sites --connection-name ${basename}webconnection
ipwithlf=$(az network private-endpoint show --name ${basename}webappprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv)
ipwithoutlf=${ipwithlf//$'\r'}
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --record-set-name $webAppName --ipv4-address $ipwithoutlf

echo setting up private endpoint for function app $functionAppName
resIdcr=$(az functionapp show --name $functionAppName --resource-group $resourceGroup --query id --output tsv)
resourceId=${resIdcr//$'\r'}
az network private-endpoint create --resource-group $resourceGroup --name ${basename}fnappprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id sites --connection-name ${basename}fnconnection
ipwithlf=$(az network private-endpoint show --name ${basename}fnappprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv)
ipwithoutlf=${ipwithlf//$'\r'}
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --record-set-name $functionAppName --ipv4-address $ipwithoutlf 

poolbackendaddress1=${basename}fnappprivateendpoint.azurewebsites.net
poolbackendaddress2=${basename}webappprivateendpoint.azurewebsites.net

echo Setting up application gateway  $appGatewayName
az network application-gateway create --resource-group $resourceGroup --name $appGatewayName --vnet-name $vnetName --subnet $subnet1Name --capacity $agcap --http-settings-cookie-based-affinity Enabled --sku $agsku --public-ip-address $publicIPName --servers ${basename}functionapp.azurewebsites.net --priority 1

echo Setting up acs instance $acsServiceName 
az communication create --data-location global --name $acsServiceName --resource-group $resourceGroup --mi-system-assigned

echo done! 

# # # # # # # # # # # # # # # # # # # # # 
# Security Wise we also need some tags :) 
# # # # # # # # # # # # # # # # # # # # #

# Force tunnel all traffic on the vnet 
# Add Outbound NSG rule for VNet Web App -> AzureBotService

# Deploy Bot Service
# Deploy Bot Channels Registration

