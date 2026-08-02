resource "oci_monitoring_alarm" "high_cpu" {
  compartment_id        = var.compartment_id
  display_name          = "${var.context.project_name}-high-cpu"
  metric_compartment_id = var.compartment_id
  namespace             = "oci_computeagent"
  query                 = "CpuUtilization[5m].mean() > 85"
  severity              = "WARNING"
  destinations          = [oci_ons_notification_topic.alerts.id]
  is_enabled            = true
  message_format        = "ONS_OPTIMIZED"
  pending_duration      = "PT5M"
}

resource "oci_monitoring_alarm" "high_memory" {
  compartment_id        = var.compartment_id
  display_name          = "${var.context.project_name}-high-memory"
  metric_compartment_id = var.compartment_id
  namespace             = "oci_computeagent"
  query                 = "MemoryUtilization[5m].mean() > 85"
  severity              = "WARNING"
  destinations          = [oci_ons_notification_topic.alerts.id]
  is_enabled            = true
  message_format        = "ONS_OPTIMIZED"
  pending_duration      = "PT5M"
}

resource "oci_ons_notification_topic" "alerts" {
  compartment_id = var.compartment_id
  name           = "${var.context.project_name}-alerts"
  description    = "Alert notifications for ${var.context.project_name}"
}

resource "oci_ons_subscription" "email_alert" {
  count          = var.alert_email != "" ? 1 : 0
  compartment_id = var.compartment_id
  topic_id       = oci_ons_notification_topic.alerts.id
  endpoint       = var.alert_email
  protocol       = "EMAIL"
}
