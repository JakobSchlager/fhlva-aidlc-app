## Purpose

Specifies requirements for the `modules/network` Terraform module, which provisions the Virtual Network topology, Application Gateway, and Network Security Group for the Beer Tracker application on Azure.
## Requirements
### Requirement: VNet and subnet provisioning
The `modules/network` Terraform module SHALL create a Virtual Network with address space `10.0.0.0/16` containing three subnets: `aks-subnet` (`10.0.1.0/24`), `appgw-subnet` (`10.0.2.0/24`), and `postgres-subnet` (`10.0.3.0/24`). The `postgres-subnet` SHALL carry a `Microsoft.DBforPostgreSQL/flexibleServers` service delegation to support future Flexible Server VNet integration.

#### Scenario: VNet created with correct address space
- **WHEN** the network module is applied with a project name and environment
- **THEN** a VNet named `<project>-<env>-vnet` SHALL exist in the target resource group with address prefix `10.0.0.0/16`

#### Scenario: All three subnets exist with correct CIDRs
- **WHEN** the network module is applied
- **THEN** `aks-subnet` SHALL have prefix `10.0.1.0/24`, `appgw-subnet` SHALL have prefix `10.0.2.0/24`, and `postgres-subnet` SHALL have prefix `10.0.3.0/24`

#### Scenario: Postgres subnet carries service delegation
- **WHEN** the network module is applied
- **THEN** `postgres-subnet` SHALL have a delegation for `Microsoft.DBforPostgreSQL/flexibleServers`

### Requirement: Application Gateway provisioning
The `modules/network` module SHALL create an Application Gateway (SKU `Standard_v2`) with a static Standard-tier public IP address. The gateway SHALL be attached to `appgw-subnet` and SHALL be pre-configured with a minimal placeholder routing rule (HTTP port 80) so that the AGIC addon can take over routing at runtime.

#### Scenario: Application Gateway and public IP created
- **WHEN** the network module is applied
- **THEN** an Application Gateway named `<project>-<env>-appgw` SHALL exist with a static public IP named `<project>-<env>-appgw-pip`

#### Scenario: Application Gateway uses Standard_v2 SKU with autoscaling
- **WHEN** the network module is applied
- **THEN** the Application Gateway SKU SHALL be `Standard_v2` with autoscale minimum capacity 1 and maximum capacity 10

#### Scenario: Module outputs the Application Gateway resource ID and public IP
- **WHEN** the network module is applied
- **THEN** outputs `app_gw_id`, `app_gw_name`, and `app_gw_public_ip` SHALL be populated

### Requirement: Ingress IP allowlist via NSG
The `modules/network` module SHALL accept a `ingress_allowed_ips` variable of type `list(string)`. It SHALL create a Network Security Group (NSG) attached to `appgw-subnet` with an inbound rule that permits TCP traffic on ports 80 and 443 only from the CIDRs in `ingress_allowed_ips`. All other inbound traffic on those ports SHALL be denied by a lower-priority deny rule.

#### Scenario: Traffic from an allowed IP reaches port 80
- **WHEN** `ingress_allowed_ips` contains CIDR `203.0.113.0/24` and a request originates from `203.0.113.10`
- **THEN** the NSG inbound rule SHALL permit TCP port 80 traffic

#### Scenario: Traffic from a non-listed IP is denied on port 80
- **WHEN** `ingress_allowed_ips` does not contain `198.51.100.5`
- **THEN** the NSG inbound deny rule SHALL block TCP port 80 traffic from that address

#### Scenario: NSG is associated with appgw-subnet
- **WHEN** the network module is applied
- **THEN** the NSG SHALL be associated with `appgw-subnet` and SHALL NOT be associated with `aks-subnet` or `postgres-subnet`

### Requirement: Module outputs for downstream consumers
The `modules/network` module SHALL expose the following outputs so that the `aks` module, and the root module's cross-module role assignments, can reference network resources without repeating resource lookups.

#### Scenario: Required outputs are present after apply
- **WHEN** the network module is applied
- **THEN** the following outputs SHALL be non-empty: `vnet_id`, `vnet_name`, `aks_subnet_id`, `appgw_subnet_id`, `postgres_subnet_id`, `app_gw_id`, `app_gw_name`, `app_gw_public_ip`

