# variables.tf
# Inputs for the tagged-bucket module. Every variable typed and validated
# where the constraint is meaningful.

variable "name" {
  description = "Logical name for the bucket. Forms part of the final bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 chars, lowercase alphanumeric + hyphens."
  }
}

variable "name_prefix" {
  description = "Prefix prepended to the bucket name (e.g. environment-app)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,30}$", var.name_prefix))
    error_message = "name_prefix must be 2-30 chars, lowercase alphanumeric + hyphens."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS. If null, the bucket uses SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "noncurrent_version_expiration_days" {
  description = "Days before noncurrent versions expire."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1 && var.noncurrent_version_expiration_days <= 3650
    error_message = "noncurrent_version_expiration_days must be between 1 and 3650."
  }
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a non-empty bucket. Disable for prod."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags merged on top of provider default_tags."
  type        = map(string)
  default     = {}
}
