# variables.tf
# Representative examples: validated string, number with validation block,
# object with optional() fields, sensitive variable.

variable "environment" {
  description = "Deployment environment. One of dev, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "app" {
  description = "Application name; lowercase alphanumeric and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,30}$", var.app))
    error_message = "app must be 2-30 chars, lowercase alphanumeric + hyphens."
  }
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Team or individual owning these resources."
  type        = string
  nullable    = false
}

variable "repo_url" {
  description = "URL of the repository defining this stack; tagged on resources."
  type        = string
}

variable "lifecycle_days" {
  description = "Days before noncurrent S3 versions transition to Glacier."
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_days >= 30 && var.lifecycle_days <= 3650
    error_message = "lifecycle_days must be between 30 and 3650."
  }
}

variable "vpc_config" {
  description = "Optional VPC configuration; fields default if omitted."
  type = object({
    cidr             = string
    enable_flow_logs = optional(bool, true)
    azs              = optional(list(string))
  })
  default = null
}

variable "tags" {
  description = "Additional tags merged on top of provider default_tags."
  type        = map(string)
  default     = {}
}

variable "db_password" {
  description = "RDS master password. Source from Secrets Manager in CI; never commit."
  type        = string
  sensitive   = true
  nullable    = false
  default     = null
}
