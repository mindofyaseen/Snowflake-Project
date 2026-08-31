output "connector_id" {
  description = "Connector controlled by this stack."
  value       = var.connector_id
}

output "sync_frequency_minutes" {
  description = "Configured automatic sync interval."
  value       = var.sync_frequency
}

output "pause_after_trial" {
  description = "Whether Fivetran will automatically pause after the trial."
  value       = var.pause_after_trial
}
