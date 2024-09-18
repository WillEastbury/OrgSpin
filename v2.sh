!#/bin/bash
# This script creates a resource group and deploys a set of resources to Azure

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

#basename="wieastdemo"
#location="uksouth"
basename=$1
location=$2

resourceGroup="${basename}rg"
cosmosDbAccount="${basename}cosmosdb"
cosmosDbDatabase="${basename}db"
openAIName="${basename}openai"
appServicePlan="${basename}appserviceplan"
webAppName="${basename}webapp"
functionAppName="${basename}functionapp"
storageAccountName="${basename}storage"
vnetName="${basename}vnet"
addressPrefix="10.0.0.0/16"
subnet1Name="${vnetName}subnet1"
subnet2Name="${vnetName}subnet2"
subnet1Prefix="10.0.1.0/24"
subnet2Prefix="10.0.2.0/24"
appGatewayName="${basename}appgateway"
publicIPName="${basename}publicip"
botServiceName="${basename}botservice"
appServicePlanSku="F1"
cogServSku="S0"
cogServAcctType="OpenAI"
agsku="Standard_v2"
agcap=1

appId="your-app-id" 
appPassword="your-app-password"

az group create --name $resourceGroup --location $location
az network vnet create --resource-group $resourceGroup --name $vnetName --address-prefix $addressPrefix --location $location
az network vnet subnet create --resource-group $resourceGroup --vnet-name $vnetName --name $subnet1Name --address-prefix $subnet1Prefix
az network vnet subnet create --resource-group $resourceGroup --vnet-name $vnetName --name $subnet2Name --address-prefix $subnet2Prefix
az network public-ip create --resource-group $resourceGroup --name $publicIPName --allocation-method Static

az cognitiveservices account create --name $openAIName --resource-group $resourceGroup --kind $cogServAcctType --sku $cogServSku --location $location
az storage account create --name $storageAccountName --resource-group $resourceGroup --location $location --sku Standard_LRS
az appservice plan create --name $appServicePlan --resource-group $resourceGroup --location $location --sku $appServicePlanSku 
az webapp create --name $webAppName --resource-group $resourceGroup --plan $appServicePlan
az functionapp create --resource-group $resourceGroup --consumption-plan-location $location --runtime dotnet --name $functionAppName --storage-account $storageAccountName
az cosmosdb create --name $cosmosDbAccount --resource-group $resourceGroup --locations regionName=$location
az cosmosdb sql database create --account-name $cosmosDbAccount --resource-group $resourceGroup --name $cosmosDbDatabase
az cosmosdb sql container create --account-name $cosmosDbAccount --resource-group $resourceGroup --database-name $cosmosDbDatabase --name "items" --partition-key-path "/id"
#az bot create --resource-group $resourceGroup --name $botServiceName --sku F0 --location $location --app-type registration --appid $appId
#az bot create --resource-group $resourceGroup --name $botServiceName --sku F0 --appid myAppId --app-type registration --endpoint "https://${webAppName}azurewebsites.net/api/messages"} --kind registration --password password
resourceId=$(az cognitiveservices account show --name $openAIName --resource-group $resourceGroup --query id --output tsv)
az resource update --ids $resourceId --set properties.networkAcls="{'defaultAction':'Deny'}"

az network private-endpoint create --resource-group $resourceGroup --name ${basename}cogservprivateendpoint    --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $(az cognitiveservices account show --name $openAIName --resource-group $resourceGroup --query id --output tsv) --group-id cognitiveServices    --connection-name ${basename}cogservconnection 
az network private-endpoint create --resource-group $resourceGroup --name ${basename}cosmosdbprivateendpoint   --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $(az cosmosdb show --name $cosmosDbAccount --resource-group $resourceGroup --query id --output tsv)             --group-id sql                  --connection-name ${basename}sqlconnection
az network private-endpoint create --resource-group $resourceGroup --name ${basename}functionapprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $(az functionapp show --name $functionAppName --resource-group $resourceGroup --query id --output tsv)          --group-id function             --connection-name ${basename}fnconnection
az network private-endpoint create --resource-group $resourceGroup --name ${basename}webappprivateendpoint     --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $(az webapp show --name $webAppName --resource-group $resourceGroup --query id --output tsv)                    --group-id websites             --connection-name ${basename}webconnection

az network private-dns zone create --resource-group $resourceGroup --name privatelink.cognitiveservices.azure.com
az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.cognitiveservices.azure.com --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.cognitiveservices.azure.com --record-set-name $openAIName --ipv4-address $(az network private-endpoint show --name ${basename}cogservprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)

az network private-dns zone create --resource-group $resourceGroup --name privatelink.documents.azure.com
az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.documents.azure.com --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.documents.azure.com --record-set-name $cosmosDbAccount --ipv4-address $(az network private-endpoint show --name ${basename}cosmosdbprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)

az network private-dns zone create --resource-group $resourceGroup --name privatelink.azurewebsites.net 
az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --record-set-name $webAppName --ipv4-address $(az network private-endpoint show --name ${basename}webappprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)
az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --record-set-name $functionAppName --ipv4-address $(az network private-endpoint show --name ${basename}functionapprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)

az network application-gateway create --resource-group $resourceGroup --name $appGatewayName --vnet-name $vnetName --subnet $subnet1Name --capacity $agcap --http-settings-cookie-based-affinity Enabled --sku $agsku --public-ip-address $publicIPName --frontend-port 443 --priority 1 --backend-port 443 --servers $(az network private-endpoint show --name ${basename}webappprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)
az network application-gateway address-pool create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}webappbackendpool --servers $(az network private-endpoint show --name ${basename}webappprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)
az network application-gateway address-pool create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}functionappbackendpool --servers $(az network private-endpoint show --name ${basename}functionapprivateendpoint --resource-group $resourceGroup --query privateLinkServiceConnections[0].privateLinkServiceConnectionState.status --output tsv)
az network application-gateway http-settings create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}webappsettings --port 80 --protocol Http --cookie-based-affinity Disabled --timeout 20 --request-timeout 20 --connection-draining-timeout 0 --probe ${basename}webappprobe --backend-pool ${basename}webappbackendpool
az network application-gateway http-settings create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}functionappsettings --port 80 --protocol Http --cookie-based-affinity Disabled --timeout 20 --request-timeout 20 --connection-draining-timeout 0 --probe ${basename}functionappprobe --backend-pool ${basename}functionappbackendpool
az network application-gateway listener create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}listener --frontend-port 80 --frontend-ip ${basename}frontendip --protocol Http
az network application-gateway url-path-map create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}webapprule --default-backend-address-pool ${basename}webappbackendpool --default-backend-http-settings ${basename}webappsettings --path-rules "/webapp/*=${basename}webappbackendpool"
az network application-gateway url-path-map create --resource-group $resourceGroup --gateway-name $appGatewayName --name ${basename}functionapprule --default-backend-address-pool ${basename}functionappbackendpool --default-backend-http-settings ${basename}functionappsettings --path-rules "/api/*=${basename}functionappbackendpool"

