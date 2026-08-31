variable "connector_id" {
  description = "Fivetran connector ID from the connector status or setup page."
  type        = string

  validation {
    condition     = length(trimspace(var.connector_id)) > 0
    error_message = "connector_id must not be empty."
  }
}

variable "sync_frequency" {
  description = "Sync interval in minutes supported by Fivetran."
  type        = string
  default     = "360"

  validation {
    condition     = contains(["1", "5", "15", "30", "60", "120", "180", "360", "480", "720", "1440"], var.sync_frequency)
    error_message = "sync_frequency must be a Fivetran-supported interval."
  }
}

variable "paused" {
  description = "Pause or enable the connector schedule."
  type        = bool
  default     = false
}

variable "pause_after_trial" {
  description = "Automatically pause the connector when its free trial ends."
  type        = bool
  default     = true
}
