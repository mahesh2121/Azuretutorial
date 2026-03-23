# AVM Implementation Documentation: Azure Container Registry & Azure Container Instances

## 1. Architecture Overview & Achievements
- **Deployed Private ACR**: Created an Azure Container Registry (Premium SKU) using the official AVM module, integrated fully with a Virtual Network via a Private Endpoint and Private DNS Zone.
- **Fixed ACI Definitions**: Converted an existing Azure Container Instance AVM configuration to correctly utilize valid Terraform variable definitions instead of invalid `.tfvars` structures.
- **Integrated Secure Pulling**: Connected the ACI to the private ACR by providing the Container Group with a User-Assigned Managed Identity, granting it the `AcrPull` role, and instructing the AVM module to use this identity for image pulling.
- **Successfully Verified**: Pushed an initial `nginx:latest` image to the ACR and spun up the ACI, proving out the end-to-end pull process over the Azure secure backbone (Trusted Services) without exposing the ACR to the public internet.

## 2. Challenges & Resolutions
- **Issue: Terraform Provider Version Conflicts**
  - **Symptom:** The root container instance module required `azurerm ~> 4.0`, but the local example module required `~> 3.71`.
  - **Resolution:** Adjusted the root `main.tf` provider constraint to `~> 3.74` which satisfied the intersection of all downstream modules requirements and resolved the 404 SubscriptionNotFound provider cache errors during `init`.
- **Issue: Terraform Variable Syntax Errors**
  - **Symptom:** The initial `variables.tf` file contained `.tfvars` style assigning (`variable = "value"`) instead of `variable` block declarations.
  - **Resolution:** Purged the invalid assignment variables and created proper `variable` definition blocks. Values were kept entirely within `terraform.tfvars`.

## 3. Explaining the `image_registry_credential` Workaround
When configuring strict AVM modules with mutually exclusive authentication mechanisms, you often run into schema validation errors. This was the case for the `image_registry_credential` block:

```hcl
  image_registry_credential = {
    cred1 = {
      user_assigned_identity_id = azurerm_user_assigned_identity.this.id
      server                    = data.azurerm_container_registry.acr.login_server
      username                  = null
      password                  = null
    }
  }
```

* **`user_assigned_identity_id`**: Tells the ACI to authenticate using the Managed Identity we created, which has already been granted the `AcrPull` permission.
* **`server`**: Tells ACI which specific registry it is trying to authenticate against.
* **`username = null` and `password = null`**: 
  * **The AVM Module Schema Requirement**: The official Azure Verified Module (AVM) code strictly defines the object type map to heavily expect all four fields to be typed out, even if you are only using the Managed Identity. 
  * **The Azurerm Provider Rule**: If you provide a `username` or `password` as an empty string (`""`), the provider will aggressively reject it and crash, stating that if a username/password is provided, it *must* contain actual characters (validation violation).
  * **The `null` Solution**: By explicitly setting them to `null`, we satisfy the AVM module's structural requirement (the required keys exist in the configuration map), but we tell Terraform's core engine to literally drop the fields before handing them to Azure API calls. Azure only sees the `user_assigned_identity_id` and securely processes the pull across Trusted Services!

## 4. ABAC (Attribute-Based Access Control) Implementation
**Can ABAC be implemented directly inside the AVM module, or does it require external resources?**

ABAC **CAN be implemented natively inside both the AVM ACR and AVM ACI modules!** You do not necessarily have to create an external `azurerm_role_assignment` resource unless the specific assignment scope requires it.

Azure ABAC logic is implemented using **Role Assignment Conditions**. If you examine the `role_assignments` variable schema native to the Azure Verified Modules, it fully supports the `condition` and `condition_version` optional attributes.

**Example of implementing ABAC inside an AVM module (like your `main.tf` configuration):**

```hcl
module "registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  # ... core networking configuration ...

  role_assignments = {
    abac_assignment = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = "your-principal-id-here"
      
      # >> ABAC Conditions Supported Native to AVM <<
      condition_version          = "2.0"
      condition                  = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Resource[Microsoft.Authorization/roleAssignments:PrincipalType] StringEqualsIgnoreCase 'ServicePrincipal'))"
    }
  }
}
```
By simply providing your Azure ABAC condition string directly to the module's `role_assignments` variable, the internally embedded role assignment handles the complex ABAC policy for you securely and conveniently.
