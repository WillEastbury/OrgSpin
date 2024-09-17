# OrgSpin
Scripts and utilities to drive the creation of a spin up of a full enterprise-level demonstration subscription in Azure

The plan for this is make the creation of disposable demo environments easier than it currently is, for all users. 

Eventually we may choose to move this into the azure-samples repo, but for now this is an external effort. 

## Base Build

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
- Azure Private Link: For securely connecting services like SQL Database, Storage, or your own services, through private endpoints.
- Azure Files
  
## Deployment enhancements 

### Identity and Access Management:
- Entra ID Conditional Access: Policies to enforce security rules based on the user, location, and device compliance.
- Entra ID Privileged Identity Management (PIM): Manage, control, and monitor access to critical resources in Azure to limit standing admin access.
- Entra ID External Identities : Extend your AD to handle customers (B2C) or external partners (B2B) securely.
- Multi-Factor Authentication (MFA): Enforcing MFA on Entra AD identities for an extra layer of security.

### Monitoring and management dashboard 
- Azure Monitor: Centralized monitoring for logs, metrics, and telemetry from all Azure services.
- Azure Application Insights: For detailed performance monitoring and diagnostics of web applications.
- Azure Log Analytics: Collect and analyze data from resources, with powerful querying and alerting capabilities.
- Azure Security Center (Microsoft Defender for Cloud): A unified infrastructure security management system that strengthens your security posture.
- Azure Policy: Enforcing organizational standards and assessing compliance at scale.

### Backup and Restore testing and Business Continuity Sample 
- Disaster recovery testing.
- Deployment Pipeline Exports and deployment redirection
- Azure Backup

### Further Networking
- Azure Load Balancers
- Azure Traffic Manager
- Azure Front Door
- Certificate Management - and Internal CA
- VWAN ?? 
- Azure DDoS Protection

### Pluggable Services
- Azure Queue Storage/Service Bus: For reliable messaging between distributed applications.
- Azure API Management: Publish and manage APIs to internal and external clients.
- Azure Event Grid: A managed event routing service to handle communication between services and applications.
- Azure Logic Apps: Automating workflows and business processes by integrating with various services.
- Azure Functions: Serverless computing for event-driven workloads (ideal for microservices and event handling).

### Other licences to apply / consider
- Microsoft 365 Integration (Exchange, Teams, Sharepoint) 
- Microsoft Intune
- Power Platform
- SAP HANA
- Azure Arc
