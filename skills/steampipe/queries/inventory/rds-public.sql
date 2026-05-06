-- Title: Publicly Accessible RDS Instances
-- Description: Returns RDS instances whose `publicly_accessible` flag is
-- true. Includes encryption and backup-window context so the row is
-- self-contained for review.
select
    account_id,
    region,
    db_instance_identifier,
    engine,
    engine_version,
    class                       as instance_class,
    publicly_accessible,
    storage_encrypted,
    kms_key_id,
    backup_retention_period,
    multi_az,
    endpoint_address,
    endpoint_port,
    create_time
from
    aws_rds_db_instance
where
    publicly_accessible = true
order by
    account_id,
    region,
    db_instance_identifier
