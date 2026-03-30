variable "environment" {
  description = "Deployment environment segment used in Azure resource names (e.g. dev, staging)."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources in this configuration."
  type        = string
  default     = "East US"
}
