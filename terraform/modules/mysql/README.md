# Module: mysql

Provisions a MySQL HeatWave Free DB system on OCI.

## Resources

- `oci_mysql_mysql_db_system` — MySQL HeatWave Free instance (shape `MySQL.Free`)

## Notes

- Deployed into the private subnet; not reachable from the internet.
- `admin_password` is marked `sensitive` and never logged.
- Daily automated backups retained for 7 days.

## Outputs

| Name          | Description                        |
|---------------|------------------------------------|
| `db_system_id`| OCID of the MySQL DB system        |
| `endpoint`    | `host:port` connection string      |
| `ip_address`  | Private IP of the DB system        |
