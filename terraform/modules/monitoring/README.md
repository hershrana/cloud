# Module: monitoring

Creates OCI Monitoring alarms and an ONS notification topic for operational alerts.

## Alarms

| Alarm          | Condition                          | Severity |
|----------------|------------------------------------|----------|
| `high-cpu`     | CPU utilisation > 85% for 5 min    | WARNING  |
| `high-memory`  | Memory utilisation > 85% for 5 min | WARNING  |

## Outputs

| Name                    | Description                      |
|-------------------------|----------------------------------|
| `notification_topic_id` | OCID of the ONS notification topic|
