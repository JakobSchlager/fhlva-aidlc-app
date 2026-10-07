## MODIFIED Requirements

### Requirement: Module outputs for downstream consumers
The `modules/network` module SHALL expose the following outputs so that the `aks` module, and the root module's cross-module role assignments, can reference network resources without repeating resource lookups.

#### Scenario: Required outputs are present after apply
- **WHEN** the network module is applied
- **THEN** the following outputs SHALL be non-empty: `vnet_id`, `vnet_name`, `aks_subnet_id`, `appgw_subnet_id`, `postgres_subnet_id`, `app_gw_id`, `app_gw_name`, `app_gw_public_ip`
