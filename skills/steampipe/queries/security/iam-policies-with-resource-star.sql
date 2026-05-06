-- Title: IAM Policies Granting Action=* on Resource=*
-- Description: Unwraps the normalized `policy_std` JSONB document and flags
-- any Allow statement that grants `*` on `*`. Uses the JSONB containment
-- operator `@>` to handle both single-string and list-shaped Action /
-- Resource fields without special-casing them.
select
    account_id,
    name                            as policy_name,
    arn                             as policy_arn,
    is_aws_managed,
    statement ->> 'Sid'             as statement_sid,
    statement ->> 'Effect'          as effect,
    statement -> 'Action'           as actions,
    statement -> 'Resource'         as resources
from
    aws_iam_policy,
    jsonb_array_elements(policy_std -> 'Statement') as statement
where
    statement ->> 'Effect' = 'Allow'
    and statement -> 'Action'   @> '"*"'
    and statement -> 'Resource' @> '"*"'
order by
    is_aws_managed,
    account_id,
    policy_name
