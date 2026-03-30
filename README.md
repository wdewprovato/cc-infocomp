# Terraform — cc-infocomp Azure infrastructure

This configuration provisions Azure resources for the infocomp workload: resource groups, networking (VNet and subnets), Terraform remote-state storage, app storage (table), Windows App Service with private endpoint, Application Insights, Log Analytics, and Key Vault with private endpoint.

## Requirements

- [Terraform](https://www.terraform.io/downloads) `>= 1.6` (CI uses `1.9.x`)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) logged in (`az login`) for local runs
- An Azure subscription with permissions to create the resources below

## Repository layout

| Path | Purpose |
|------|---------|
| `main.tf` | Core resources |
| `versions.tf` | Terraform and provider versions; `backend "azurerm"` (config supplied at init) |
| `providers.tf` | `azurerm` provider |
| `variables.tf` | Input variables |
| `outputs.tf` | Exported values after apply |
| `config/*.backend.hcl.example` | Example remote backend settings |
| `terraform.tfvars.example` | Example variable file (copy to `terraform.tfvars`, gitignored if you use `*.auto.tfvars` patterns) |

Commit **`.terraform.lock.hcl`** so everyone and CI use the same provider builds.

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `environment` | Short name embedded in Azure resource names (e.g. `dev`, `staging`) | `dev` |
| `location` | Azure region | `East US` |

Override with `-var` or a `*.tfvars` file:

```bash
terraform plan -var="environment=staging"
```

See `terraform.tfvars.example`.

## Remote state (Azure Storage)

The module defines a **state** resource group, storage account, and blob container. Using that same storage as the **backend** before it exists is a bootstrap problem. Pick one approach:

1. **Local state first, then migrate**  
   - `terraform init -backend=false`  
   - `terraform apply` (creates state storage)  
   - `terraform init -migrate-state -backend-config=config/<env>.backend.hcl`  

2. **Bootstrap by hand**  
   Create the state RG, storage account (name must match the module’s rules: alphanumeric only, 3–24 chars), and container, then point `backend` at them.

Example backend values for default `environment = "dev"` are in [`config/dev.backend.hcl.example`](config/dev.backend.hcl.example). It sets **`use_azuread_auth = true`** so `az login` works without a storage access key; your identity still needs **Storage Blob Data Contributor** on the state storage account (or the blob container). Include **`resource_group_name`** in that file—interactive `terraform init` often omits it and triggers “Either an Access Key / SAS Token or the Resource Group…”.

Copy to `config/dev.backend.hcl` (gitignored) and run:

```bash
cd terraform
terraform init -backend-config=config/dev.backend.hcl
```

State object key used in GitHub Actions: `infocomp/<environment>/terraform.tfstate`.

## Common local commands

```bash
cd terraform
terraform fmt -recursive
terraform init -backend-config=config/dev.backend.hcl   # or -backend=false
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

## GitHub Actions

Workflow: [`.github/workflows/terraform.yml`](../.github/workflows/terraform.yml).

- **Pull requests** and **pushes to `main`** (when `terraform/` changes): format check, init, validate, **plan**, upload plan text as an artifact.
- **Apply** runs only on **workflow_dispatch** when **Run apply** is enabled (not on merge by default).

### Secrets

| Secret | Purpose |
|--------|---------|
| `AZURE_CLIENT_ID` | App registration application (client) ID |
| `AZURE_CLIENT_SECRET` | App registration client secret |
| `AZURE_TENANT_ID` | Microsoft Entra tenant |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `TF_BACKEND_RESOURCE_GROUP` | RG that contains the state storage account |
| `TF_BACKEND_STORAGE_ACCOUNT` | State storage account name |
| `TF_BACKEND_CONTAINER` | Blob container name for state |

### Optional repository variable

- **`TF_ENVIRONMENT`** — Used for `TF_VAR_environment` and the state blob key on PR/push workflows when not using `workflow_dispatch`. If unset, **`dev`** is used.

### Azure app registration for GitHub

Create an **app registration**, add a **client secret**, and store it as **`AZURE_CLIENT_SECRET`**. Assign the app **RBAC on the subscription** (e.g. Contributor, or a custom role) for Terraform resources, and **Storage Blob Data Contributor** on the Terraform state storage account so the remote backend can use `use_azuread_auth`.

## Outputs

Notable outputs include resource group names, VNet ID, web app name and default hostname, Key Vault URI, storage account names, and a **sensitive** Application Insights connection string. Run `terraform output` after apply.

## Naming notes

- Storage account names are **globally unique**, **lowercase alphanumeric only**, length **3–24**. The module derives names from `environment`; very long environment strings are normalized and truncated—prefer short labels (`dev`, `stg`, `prd`).

## Provider

- **azurerm** `~> 4.66` (see `versions.tf`).

`azurerm_app_service_plan` is deprecated in favor of `azurerm_service_plan`; migrating is optional and may affect resource addressing in state.
