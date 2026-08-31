resource "fivetran_connector_schedule" "selected" {
  connector_id      = var.connector_id
  sync_frequency    = var.sync_frequency
  paused            = var.paused
  pause_after_trial = var.pause_after_trial
  schedule_type     = "auto"
}
