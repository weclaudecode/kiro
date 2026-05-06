# AWS-Specific Code Review

Cloud SDKs introduce their own sinks. The reviewer looks for the patterns
below in boto3 and other AWS SDK call sites.

## Patterns to Find

- **Overly broad boto3 parameters.** `s3.list_objects_v2(Bucket=user_bucket)`
  where `user_bucket` is user-controlled — caller can enumerate any bucket
  the role has access to.
- **`s3:GetObject` without ownership validation.** The code reads
  `s3://app-uploads/{user_path}` where `user_path` came from the request and
  was not prefix-validated against the caller's tenant.
- **`assume_role` cross-account without `ExternalId`.** Confused-deputy
  vulnerability. Always pass `ExternalId` for third-party cross-account
  roles.
- **Pre-signed URLs with long expiry.**
  `generate_presigned_url(... ExpiresIn=604800)` (7 days). Default to
  minutes, not days. Never pass user-controlled `ExpiresIn`.
- **DynamoDB scan with user filter.** `scan(FilterExpression=...)` driven by
  user input is O(table) and lets the user enumerate. Use
  `KeyConditionExpression` against an index, scoped to the caller's tenant
  partition key.
- **SQS/SNS with attacker-controlled queue ARN.** Sending to a user-supplied
  ARN can pivot to other accounts.
- **Lambda environment variables containing secrets.** Use Secrets Manager
  or Parameter Store; environment variables in Lambda are visible to anyone
  with `lambda:GetFunction`.
- **KMS `Decrypt` without `EncryptionContext`.** Loses the audit-trail
  binding between the ciphertext and its intended use.
- **STS GetCallerIdentity used as authorization.** Confirms who the caller
  is but says nothing about whether they should be allowed; pair with an
  explicit principal check.

## Examples

```python
# Vulnerable — caller controls the prefix
def get_user_file(key):
    return s3.get_object(Bucket="app-uploads", Key=key)

# Fixed — bind to authenticated tenant
def get_user_file(tenant_id, key):
    if not key.startswith(f"tenants/{tenant_id}/"):
        raise PermissionError()
    return s3.get_object(Bucket="app-uploads", Key=key)
```

```python
# Vulnerable — 7-day pre-signed URL, user-controlled expiry
url = s3.generate_presigned_url(
    "get_object",
    Params={"Bucket": bucket, "Key": key},
    ExpiresIn=int(request.args["ttl"]),
)

# Fixed — short fixed expiry, server-controlled
url = s3.generate_presigned_url(
    "get_object",
    Params={"Bucket": bucket, "Key": key},
    ExpiresIn=300,
)
```

```python
# Vulnerable — cross-account assume_role with no ExternalId
sts.assume_role(RoleArn=customer_role_arn, RoleSessionName="svc")

# Fixed — bind the trust to a customer-specific ExternalId
sts.assume_role(
    RoleArn=customer_role_arn,
    RoleSessionName="svc",
    ExternalId=customer_external_id,
)
```

```python
# Vulnerable — KMS Decrypt with no EncryptionContext
plaintext = kms.decrypt(CiphertextBlob=blob)["Plaintext"]

# Fixed — context binds the ciphertext to its tenant/use
plaintext = kms.decrypt(
    CiphertextBlob=blob,
    EncryptionContext={"tenant": tenant_id, "purpose": "user-export"},
)["Plaintext"]
```

```python
# Vulnerable — DynamoDB scan with user filter
table.scan(
    FilterExpression="attribute_exists(email) AND contains(email, :q)",
    ExpressionAttributeValues={":q": user_query},
)

# Fixed — query an index, scoped to tenant
table.query(
    IndexName="tenant-email-index",
    KeyConditionExpression="tenant_id = :t AND begins_with(email, :q)",
    ExpressionAttributeValues={":t": tenant_id, ":q": user_query},
)
```
