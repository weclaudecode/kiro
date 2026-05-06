-- Title: CloudTrail Misconfiguration
-- Description: Lists trails that are not multi-region, not currently
-- logging, missing log file validation, or sending to an unencrypted S3
-- bucket. Any account that does not appear in this result either has zero
-- trails (worse) or a perfectly configured one (good) — pair with a
-- separate "accounts without any trail" check for full coverage.
select
    account_id,
    name                              as trail_name,
    home_region,
    is_multi_region_trail,
    is_logging,
    log_file_validation_enabled,
    kms_key_id,
    s3_bucket_name,
    case
        when is_logging = false                       then 'trail not logging'
        when is_multi_region_trail = false            then 'single-region trail'
        when log_file_validation_enabled = false      then 'log file validation off'
        when kms_key_id is null                       then 'logs not encrypted with KMS'
        else 'other'
    end                               as finding
from
    aws_cloudtrail_trail
where
    is_logging = false
    or is_multi_region_trail = false
    or log_file_validation_enabled = false
    or kms_key_id is null
order by
    account_id,
    home_region,
    trail_name
