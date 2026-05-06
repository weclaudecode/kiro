-- Title: Lambda Function Inventory Summary
-- Description: Per-function inventory with runtime, memory, timeout, role,
-- and last-modified date. Useful for runtime-deprecation tracking (Python
-- 3.7, Node 12/14, etc.) and for surfacing functions that haven't shipped
-- in months.
select
    account_id,
    region,
    name                  as function_name,
    runtime,
    handler,
    memory_size,
    timeout,
    role                  as execution_role_arn,
    code_size,
    last_modified,
    extract(day from now() - last_modified::timestamp) as days_since_last_deploy,
    package_type,
    architectures,
    vpc_id,
    tracing_config ->> 'Mode' as tracing_mode
from
    aws_lambda_function
order by
    account_id,
    region,
    function_name
