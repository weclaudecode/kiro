# Multi-Environment Deploys and Review Apps

## Multi-environment deploy pattern

```yaml
.deploy:
  extends: .aws-auth
  script:
    - ./scripts/deploy.sh "$CI_ENVIRONMENT_NAME"

deploy_dev:
  extends: .deploy
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::111111111111:role/gitlab-deploy-dev
  environment:
    name: dev
    url: https://dev.example.com
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy_staging:
  extends: .deploy
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::222222222222:role/gitlab-deploy-staging
  environment:
    name: staging
    url: https://staging.example.com
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
  needs: [deploy_dev]

deploy_prod:
  extends: .deploy
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::333333333333:role/gitlab-deploy-prod
  environment:
    name: production
    url: https://app.example.com
    on_stop: rollback_prod
  resource_group: production
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false
  needs: [deploy_staging]

rollback_prod:
  extends: .aws-auth
  stage: deploy
  variables:
    AWS_ROLE_ARN: arn:aws:iam::333333333333:role/gitlab-deploy-prod
  environment:
    name: production
    action: stop
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
  script: ./scripts/rollback.sh
```

Why each piece matters:

- `environment:` makes deploys show up in the GitLab Environments UI with
  a clickable URL and history. `CI_ENVIRONMENT_NAME` is then available
  to the script and to OIDC sub-claim conditions.
- `when: manual` + `allow_failure: false` for prod gates the deploy on a
  human click while still failing the pipeline if it errors after click.
- `resource_group: production` serialises prod deploys. Without it, two
  MRs merging within seconds can run two prod deploys in parallel and
  race each other.
- `on_stop:` registers a rollback job tied to the environment, callable
  from the Environments UI.

## Review apps (dynamic environments)

```yaml
review_app:
  stage: deploy
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.com
    on_stop: stop_review_app
    auto_stop_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script: ./scripts/deploy-review.sh "$CI_MERGE_REQUEST_IID"

stop_review_app:
  stage: deploy
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    action: stop
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
  script: ./scripts/teardown-review.sh "$CI_MERGE_REQUEST_IID"
```

`auto_stop_in:` cleans up zombie environments without operator action.

## Multi-account AWS deploys

The pattern: separate IAM role per AWS account, parameterise the
assume-role step by environment, pin the `sub` claim trust to the
environment name. The `deploy_dev` / `deploy_staging` / `deploy_prod`
example above is already a multi-account deploy — each environment has
its own `AWS_ROLE_ARN` pointing into a different account.

To go further, drive the role ARN purely from environment variables set
on the GitLab environment:

1. In **Settings > CI/CD > Variables**, scope variables to environments:
   `AWS_ROLE_ARN` with value `arn:...:role/gitlab-deploy-dev` scoped to
   `dev`, another scoped to `staging`, another to `production`.
2. The `.deploy` template stays generic — no hardcoded ARNs in YAML.
3. The IAM trust on each role uses
   `gitlab.example.com:sub: ".../environment:dev"` etc., so the dev role
   refuses to be assumed by a job claiming environment `production` and
   vice versa.

This pairs with infrastructure-as-code that owns the roles. See the
`terragrunt-multi-account` skill for the Terragrunt-side layout that
mirrors this account boundary, and `terraform-aws` for the IaC patterns
that provision the roles, OIDC providers, and trust policies.
