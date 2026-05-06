-- Title: Public S3 Buckets
-- Description: Returns S3 buckets that are public via bucket policy or that
-- have any of the public-block protections disabled (block_public_acls,
-- block_public_policy). Replace `aws_s3_bucket` with `aws_all.aws_s3_bucket`
-- to query all aggregator-merged accounts at once.
select
    account_id,
    region,
    name,
    bucket_policy_is_public,
    block_public_acls,
    block_public_policy,
    ignore_public_acls,
    restrict_public_buckets,
    creation_date
from
    aws_s3_bucket
where
    bucket_policy_is_public
    or block_public_acls = false
    or block_public_policy = false
    or ignore_public_acls = false
    or restrict_public_buckets = false
order by
    account_id,
    name
