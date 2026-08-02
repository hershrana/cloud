output "notification_topic_id" {
  description = "OCID of the ONS notification topic."
  value       = oci_ons_notification_topic.alerts.id
}
