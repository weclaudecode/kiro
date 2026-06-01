# Powerpipe mod for multi-environment AWS reporting.
#
# Install with:  powerpipe mod install   (run from this directory)
# Pin every dependency version — unpinned mods shift benchmarks under you
# and produce overnight false positives. Bump deliberately, review the diff.
#
# Connections (dev/staging/prod + an `all` aggregator) live in Steampipe's
# aws.spc — see the `steampipe` skill. Select an environment at run time with
# `--search-path-prefix aws_<env>`, never by editing this mod.

mod "acme_aws_reporting" {
  title         = "ACME AWS Multi-Environment Reporting"
  description   = "Security posture + cost reporting across AWS environments, built on Steampipe."
  color         = "#FF9900"

  # Pinned upstream mods. Update versions intentionally.
  require {
    mod "github.com/turbot/steampipe-mod-aws-compliance" {
      version = "1.20.0"
    }
    mod "github.com/turbot/steampipe-mod-aws-insights" {
      version = "1.5.0"
    }
  }
}
