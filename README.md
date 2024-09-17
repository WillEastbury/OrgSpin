# OrgSpin
Scripts and utilities to drive the creation of a spin up of a full enterprise-level demonstration subscription in Azure

The plan for this is make the creation of disposable demo environments easier than it currently is, for all users. 

Eventually we may choose to move this into the azure-samples repo, but for now this is an external effort. 

We will build 

- Resource groups
- 3-region vnet with multiple subnets
- VPN Gateway and configured site-to-site tunnel back to a home site
- B- Resource groups
- 3-region vnet with multiple subnets
- 3-region global peering
- Azure Bastion
- 2x Domain controllers
- 2x App gateway
- Azure Firewall
- Azure SQL environment ('server' + 'dbs)
- app service hosts
- domain controllers 
- domain sample users
- domain sample M365 and Teams setup 
- entra id setup and sync
- laptop domain join
- bot service instances
- 2x aks clusters
- 2x ac registries (cross region)
- Azure Communication Services config to Teams / Bot Service
- service endpoints for the above
- 3-region global peering
- Azure Bastion
- 2x Domain controllers
- 2x App gateway
- Azure Firewall
- Azure SQL environment ('server' + 'dbs)
- app service hosts
- 2X domain controllers 
- 2X Random App Server VMs running some weird stuff no one has the source code to
- Exchange Online Licences and some sample data
- Sharepoint Online Licences and some sample data 
- domain sample users with relevant attributes
- domain sample M365 and Teams setup 
- entra id connect setup and sync (Possibly with ADFS implementation) 
- Remote laptop cloud domain join (simulated with 2x Azure VMs in a 4th region) 
- Onprem laptop domain join (simulated with 2x Azure VMs in a separate subnet connected with the Domain Controllers)
- Print services (PDF Spooler service) 
- VM Backup and restore
- bot service instances
- 2x aks clusters
- 2x logic apps sample
- 2x ac registries (cross region)
- Azure Communication Services config to Teams / Bot Service
- service endpoints
