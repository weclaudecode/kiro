# Dashboards

A `dashboard` is a page of panels. Panels are laid out left-to-right in a
12-column grid; `width = N` sets how many columns a panel spans (panels wrap
to the next row). Group related panels in a `container`.

## Block types

| Block | Renders | Key args |
|---|---|---|
| `text` | Markdown prose | `value` |
| `card` | A single number/badge | `sql` (returns `value`, optional `label`, `type`), `type` = `ok`/`alert`/`info` |
| `chart` | Bar/column/line/donut/pie | `type`, `sql`, `axes`, `legend` |
| `table` | Rows | `sql`, `column` blocks for formatting |
| `input` | A selector (dropdown, etc.) | `type` = `select`/`text`, `sql` or static `option`s |
| `container` | A row/grouping of panels | nested panels |

## Card

```hcl
card {
  title = "Public S3 buckets"
  width = 3
  type  = "alert"                  # red when value > 0
  sql   = "select count(*) as value from aws_s3_bucket where bucket_policy_is_public;"
}
```

A card SQL returns a single row with a `value` column (optionally `label`,
`type`, `icon`).

## Chart

```hcl
chart {
  title = "Running EC2 by instance type"
  type  = "column"                 # column | bar | line | donut | pie | area
  width = 6
  sql   = <<-EOQ
    select instance_type, count(*) as instances
    from aws_ec2_instance
    where instance_state = 'running'
    group by instance_type order by instances desc;
  EOQ
}
```

First column is the category/label, subsequent numeric columns are series.

## Table with column formatting

```hcl
table {
  title = "Unattached EBS volumes"
  sql   = "select volume_id, size, region, create_time from aws_ec2_volume where state = 'available' order by size desc;"
  column "volume_id" { display = "all" }
  column "size"      { display = "all" }
}
```

## Inputs and `args`

Inputs let a viewer parameterize a dashboard interactively. The input value
flows into panel SQL via `args`:

```hcl
input "region" {
  title = "Region"
  type  = "select"
  width = 3
  sql   = "select distinct region as label, region as value from aws_region order by region;"
}

chart {
  title = "EC2 in selected region"
  sql   = "select instance_type, count(*) from aws_ec2_instance where region = $1 group by instance_type;"
  args  = [self.input.region.value]
}
```

> Environment selection (dev/staging/prod) is **not** an input — it's done
> at run time with `--search-path-prefix aws_<env>` so the same dashboard
> serves every environment. See `multi-environment.md`.

## Running

- `powerpipe server` → interactive at `http://localhost:9033` (all dashboards).
- `powerpipe dashboard run <mod>.dashboard.<name> --output html > out.html`
  → a single static HTML artifact.
- `--output pps` → a Powerpipe **snapshot** (shareable, re-openable in the UI
  or at hub.powerpipe.io).
