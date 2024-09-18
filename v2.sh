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


functionAppAddress=${functionAppName}.azurewebsites.net
webAppAddress=${webAppName}.azurewebsites.net

appServicePlanSku="S1"
functionsSku="EP1"
cogServSku="S0"
cogServAcctType="OpenAI"
agsku="Standard_v2"
agcap=1
acsdatalocation="uk"

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

    echo creating cognitive services $openAIName
        az cognitiveservices account create --name $openAIName --resource-group $resourceGroup --kind $cogServAcctType --sku $cogServSku --location $location --custom-domain $openAIName --assign-identity
        echo creating storage account $storageAccountName
        az storage account create --name $storageAccountName --resource-group $resourceGroup --location $location --sku Standard_LRS --default-action Deny

    echo creating app service $webAppName
        az appservice plan create --name $appServicePlan --resource-group $resourceGroup --location $location --sku $appServicePlanSku
        az webapp create --name $webAppName --resource-group $resourceGroup --plan $appServicePlan
        az webapp vnet-integration add --name $webAppName --resource-group $resourceGroup --vnet $vnetName --subnet $subnet3Name

    echo creating function app $functionAppName
        az functionapp plan create --name $functionAppPlanName --resource-group $resourceGroup --location $location --sku $functionsSku
        az functionapp create --resource-group $resourceGroup --runtime dotnet --name $functionAppName --storage-account $storageAccountName --plan $functionAppPlanName
        az functionapp vnet-integration add --name $functionAppName --resource-group $resourceGroup --vnet $vnetName --subnet $subnet3Name

    echo creating cosmosdb $cosmosDbAccount
        az cosmosdb create --name $cosmosDbAccount --resource-group $resourceGroup --locations regionName=$location
        az cosmosdb sql database create --account-name $cosmosDbAccount --resource-group $resourceGroup --name $cosmosDbDatabase
        az cosmosdb sql container create --account-name $cosmosDbAccount --resource-group $resourceGroup --database-name $cosmosDbDatabase --name "items" --partition-key-path "/id"

    echo creating private link infrastructure in vnet $vnetName
    echo creating private dns zones
        az network private-dns zone create --resource-group $resourceGroup --name privatelink.documents.azure.com
        az network private-dns zone create --resource-group $resourceGroup --name privatelink.cognitiveservices.azure.com
        az network private-dns zone create --resource-group $resourceGroup --name privatelink.azurewebsites.net

    echo creating private dns links to vnet $vnetName
        az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.documents.azure.com --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
        az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.cognitiveservices.azure.com --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false
        az network private-dns link vnet create --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --name ${basename}dnslink --virtual-network $vnetName --registration-enabled false

    # BUG Investigate this... Why do I have to strip the \r from the resourceId? I don't have to do this for the other resources
    # https://github.com/Azure/azure-cli/issues/21457#issuecomment-1068866984

    echo setting up private endpoint for cognitive services $openAIName in vnet $vnetName
    resIdcr=$(az cognitiveservices account show --name $openAIName --resource-group $resourceGroup --query id --output tsv) 
    resourceId=${resIdcr//$'\r'}
    az resource update --ids $resourceId --set properties.networkAcls="{'defaultAction':'Deny'}"
    az network private-endpoint create --resource-group $resourceGroup --name ${basename}cogservprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id account --connection-name ${basename}cogservconnection 
    ipwithlf=$(az network private-endpoint show --name ${basename}cogservprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv) 
    ipwithoutlf=${ipwithlf//$'\r'}
    az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.cognitiveservices.azure.com --record-set-name $openAIName --ipv4-address $ipwithoutlf

    echo setting up private endpoint for cosmosdb  $cosmosDbAccount in vnet $vnetName
    resIdcr=$(az cosmosdb show --name $cosmosDbAccount --resource-group $resourceGroup --query id --output tsv)
    resourceId=${resIdcr//$'\r'}
    az network private-endpoint create --resource-group $resourceGroup --name ${basename}cosmosdbprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id sql --connection-name ${basename}sqlconnection
    ipwithlf=$(az network private-endpoint show --name ${basename}cosmosdbprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv) 
    ipwithoutlf=${ipwithlf//$'\r'}
    az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.documents.azure.com --record-set-name $cosmosDbAccount --ipv4-address $ipwithoutlf

    echo setting up private endpoint for app service $webAppName in vnet $vnetName
    resIdcr=$(az webapp show --name $webAppName --resource-group $resourceGroup --query id --output tsv)
    resourceId=${resIdcr//$'\r'}
    az network private-endpoint create --resource-group $resourceGroup --name ${basename}webappprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id sites --connection-name ${basename}webconnection
    ipwithlf=$(az network private-endpoint show --name ${basename}webappprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv)
    ipwithoutlf=${ipwithlf//$'\r'}
    az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --record-set-name $webAppName --ipv4-address $ipwithoutlf

    echo setting up private endpoint for function app $functionAppName in vnet $vnetName
    resIdcr=$(az functionapp show --name $functionAppName --resource-group $resourceGroup --query id --output tsv)
    resourceId=${resIdcr//$'\r'}
    az network private-endpoint create --resource-group $resourceGroup --name ${basename}fnappprivateendpoint --vnet-name $vnetName --subnet $subnet2Name --private-connection-resource-id $resourceId --group-id sites --connection-name ${basename}fnconnection
    ipwithlf=$(az network private-endpoint show --name ${basename}fnappprivateendpoint --resource-group $resourceGroup --query customDnsConfigs[0].ipAddresses[0] --output tsv)
    ipwithoutlf=${ipwithlf//$'\r'}
    az network private-dns record-set a add-record --resource-group $resourceGroup --zone-name privatelink.azurewebsites.net --record-set-name $functionAppName --ipv4-address $ipwithoutlf 



echo Adding Virtual Network Service Endpoints for communication lockdown
    
    # App Gateway Subnet #1
    az network vnet subnet update --resource-group $resourceGroup --name $subnet1Name --vnet-name $vnetName --service-endpoints "Microsoft.Web" "Microsoft.KeyVault" 
    subnet1id=$(az network vnet subnet show --resource-group $resourceGroup --name $subnet1Name --vnet-name $vnetName --query id --output tsv)
    subnet1id=${subnet1id//$'\r'}
    # Private Endpoints Subnet #2
    subnet2id=$(az network vnet subnet show --resource-group $resourceGroup --name $subnet2Name --vnet-name $vnetName --query id --output tsv)
    subnet2id=${subnet2id//$'\r'}
    # Backend Webserver Subnet #3
    subnet3id=$(az network vnet subnet show --resource-group $resourceGroup --name $subnet3Name --vnet-name $vnetName --query id --output tsv)
    subnet3id=${subnet3id//$'\r'}
    az network vnet subnet update --resource-group $resourceGroup --name $subnet3Name --vnet-name $vnetName --service-endpoints "Microsoft.CognitiveServices" "Microsoft.Storage" "Microsoft.Sql" "Microsoft.Web" "Microsoft.AzureCosmosDB" "Microsoft.AzureActiveDirectory" "Microsoft.KeyVault" "Microsoft.ServiceBus"

    echo creating public ip for gateway $publicIPName
        az network public-ip create --resource-group $resourceGroup --name $publicIPName --allocation-method Static

    echo Setting up application gateway  $appGatewayName
        az network application-gateway create --resource-group $resourceGroup --name $appGatewayName --vnet-name $vnetName --subnet $subnet1Name --capacity $agcap --http-settings-cookie-based-affinity Enabled --sku $agsku --public-ip-address $publicIPName --servers $webAppAddress --priority 1

    echo Setting up acs instance $acsServiceName 
        az communication create --name $acsServiceName --resource-group $resourceGroup --mi-system-assigned --data-location $acsdatalocation --location global

fi; 

echo Now lock down services to accept access from subnet1 or subnet3 if needed

    # Storage account
    az storage account network-rule add --resource-group $resourceGroup --account-name $storageAccountName --subnet $subnet3id
    az storage account update --name $storageAccountName --resource-group $resourceGroup --default-action Deny

    # openai using PE 
    # az cognitiveservices account network-rule add --resource-group $resourceGroup --name $openAIName --subnet $subnet3id

    # cosmosdb using PE 
    # az cosmosdb network-rule add -n $cosmosDbAccount -g $resourceGroup --virtual-network $vnetName --subnet $subnet3id --ignore-missing-vnet-service-endpoint true

    # app service using pe 


    # function app using pe



echo #nsg rule addition to network 
    
    # add nsg 
    az network nsg create --resource-group $resourceGroup --name ${basename}nsg1
    az network nsg create --resource-group $resourceGroup --name ${basename}nsg2
    az network nsg create --resource-group $resourceGroup --name ${basename}nsg3

    # add nsg rules -> incoming internet traffic on ports 65200 - 65535 (AppGW Management) and 80, 443 (http, https)
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg1 --name ${basename}nsg1rule1 --priority 100 --source-address-prefixes Internet --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 65200-65535 --access Allow --protocol Tcp --description "Allow incoming internet traffic on ports 65200-65535"
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg1 --name ${basename}nsg1rule2 --priority 110 --source-address-prefixes Internet --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow --protocol Tcp --description "Allow http"
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg1 --name ${basename}nsg1rule2 --priority 120 --source-address-prefixes Internet --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow --protocol Tcp --description "Allow http"
    
    # add nsg rules -> inbound rule for vnet to appgw and probe traffic test rules
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg1 --name ${basename}nsg1rule3 --priority 130 --source-address-prefixes VirtualNetwork --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 65200-65535 --access Allow --protocol Tcp --description "Allow incoming vnet traffic on ports 65200-65535"
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg1 --name ${basename}nsg1rule4 --priority 140 --source-address-prefixes VirtualNetwork --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 80 --access Allow --protocol Tcp --description "Allow http"
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg1 --name ${basename}nsg1rule5 --priority 150 --source-address-prefixes VirtualNetwork --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 443 --access Allow --protocol Tcp --description "Allow https"
    
    # add Outbound NSG rule for VNet -> allow outbound traffic to AzureBotService tag for subnet 3
    az network nsg rule create --resource-group $resourceGroup --nsg-name ${basename}nsg3 --name ${basename}nsg3rule1 --priority 100 --source-address-prefixes VirtualNetwork --source-port-ranges '*' --destination-address-prefixes AzureBotService --destination-port-ranges '*' --access Allow --protocol Tcp --description "Allow outbound traffic to AzureBotService"

    # attach to vnet 
    az network vnet subnet update --resource-group $resourceGroup --vnet-name $vnetName --name $subnet1Name --network-security-group ${basename}nsg1
    #az network vnet subnet update --resource-group $resourceGroup --vnet-name $vnetName --name $subnet2Name --network-security-group ${basename}nsg2
    az network vnet subnet update --resource-group $resourceGroup --vnet-name $vnetName --name $subnet3Name --network-security-group ${basename}nsg3

    

    

echo done! 


# Deploy Bot Service instance 

    # az bot create --resource-group $resourceGroup --name $botServiceName --sku F0 --location $location --app-type registration --appid $appId
    # az bot create --resource-group $resourceGroup --name $botServiceName --sku F0 --appid myAppId --app-type registration --endpoint "https://${webAppName}azurewebsites.net/api/messages"} --kind registration --password password

# Deploy Bot Channels Registration and endpoint

# Deploy the web app and function apps from the app_endpoints folder 
    
    # webapp first
    # enable access from the ip [the one running the deployment script]

    # this needs the myip tool installed (myip)

    az webapp config access-restriction add --resource-group $resourceGroup --name $webAppName --rule-name 'deployment ip' --action Allow --ip-address $(myip)/32 --priority 100
    az resource update --resource-group $resourceGroup --name $webAppName --resource-type "Microsoft.Web/sites" --set properties.siteConfig.ipSecurityRestrictionsDefaultAction=Deny
    cd app_endpoints/CoreBot
    az webapp up --name $webAppName --os-type windows --runtime "DOTNET|8"

    # function app next
    # enable access from the ip [the one running the deployment script]
    
    # this needs the functions core tools installed (func.exe)
    cd ../function_app
    az functionapp config access-restriction add --resource-group $resourceGroup --name $functionAppName --rule-name 'deployment ip' --action Allow --ip-address $(myip)/32 --priority 100
    az resource update --resource-group $resourceGroup --name $functionAppName --resource-type "Microsoft.Web/sites" --set properties.siteConfig.ipSecurityRestrictionsDefaultAction=Deny
    func azure functionapp publish $functionAppName --csharp --nozip
    


