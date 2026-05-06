-- Title: IAM Users With Console Access But No MFA
-- Description: Finds IAM users who can sign in to the console
-- (password_enabled = true) but have not enrolled an MFA device. These
-- accounts are the highest-priority remediation target for any IAM audit.
select
    account_id,
    name,
    user_id,
    arn,
    create_date,
    password_last_used,
    extract(day from now() - create_date)         as account_age_days,
    extract(day from now() - password_last_used)  as days_since_login
from
    aws_iam_user
where
    password_enabled = true
    and mfa_enabled    = false
order by
    account_id,
    create_date
