// Number and date formatting. Intl formatters are expensive to construct - build once, reuse.

const LOCALE = undefined; // viewer's locale; pin (e.g. "en-US") if screenshots must be stable

const cache = new Map();
function fmt(key, factory) {
  if (!cache.has(key)) cache.set(key, factory());
  return cache.get(key);
}

export function currency(value, code = "USD", { compact = false, decimals } = {}) {
  const abs = Math.abs(value);
  // Compact: "$2.1K" but "$226" (no "$225.7"). Standard: pass decimals explicitly in tables so columns align.
  const digits = decimals ?? (compact ? (abs >= 1000 ? 1 : 0) : abs >= 1000 ? 0 : 2);
  const f = fmt(`cur:${code}:${compact}:${digits}`, () =>
    new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency: code,
      notation: compact ? "compact" : "standard",
      minimumFractionDigits: compact ? 0 : digits,
      maximumFractionDigits: digits,
    }),
  );
  return f.format(value);
}

export function number(value, { compact = false, decimals = 0 } = {}) {
  const f = fmt(`num:${compact}:${decimals}`, () =>
    new Intl.NumberFormat(LOCALE, {
      notation: compact ? "compact" : "standard",
      maximumFractionDigits: decimals,
    }),
  );
  return f.format(value);
}

export function percent(ratio, decimals = 1) {
  const f = fmt(`pct:${decimals}`, () =>
    new Intl.NumberFormat(LOCALE, { style: "percent", maximumFractionDigits: decimals, minimumFractionDigits: decimals }),
  );
  return f.format(ratio);
}

// Signed delta for text. Returns { text, dir } where dir drives color (up = spend grew = bad),
// or null when there is no usable baseline (missing or $0 previous period).
export function delta(current, previous, code = "USD") {
  if (!previous) return null;
  const diff = current - previous;
  const pct = diff / previous;
  const dir = Math.abs(pct) < 0.005 ? "flat" : diff > 0 ? "up" : "down";
  const arrow = dir === "up" ? "▲" : dir === "down" ? "▼" : "–";
  const sign = diff > 0 ? "+" : diff < 0 ? "−" : "";
  return {
    text: `${arrow} ${sign}${percent(Math.abs(pct))}`,
    abs: `${sign}${currency(Math.abs(diff), code, { compact: true })}`,
    pct,
    dir,
  };
}

// Dates are ISO "YYYY-MM-DD" strings end to end. Parse as UTC so no timezone shifts a day.
export function parseDay(iso) {
  return new Date(`${iso}T00:00:00Z`);
}

export function toDay(date) {
  return date.toISOString().slice(0, 10);
}

export function addDays(iso, n) {
  const d = parseDay(iso);
  d.setUTCDate(d.getUTCDate() + n);
  return toDay(d);
}

export function daysBetween(startIso, endIso) {
  return Math.round((parseDay(endIso) - parseDay(startIso)) / 86400000) + 1;
}

export function shortDate(iso) {
  const f = fmt("d:short", () => new Intl.DateTimeFormat(LOCALE, { month: "short", day: "numeric", timeZone: "UTC" }));
  return f.format(parseDay(iso));
}

export function longDate(iso) {
  const f = fmt("d:long", () =>
    new Intl.DateTimeFormat(LOCALE, { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" }),
  );
  return f.format(parseDay(iso));
}

// Escape anything that goes into innerHTML. Service names, tags and account names are data, not markup.
export function esc(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

// AWS billing names are long ("Amazon Elastic Compute Cloud - Compute"). Short labels for axes,
// legends and KPIs; keep the full name in tooltips, the table and CSV so nothing is ambiguous.
const AWS_SHORT = {
  "Amazon Elastic Compute Cloud - Compute": "EC2 compute",
  "EC2 - Other": "EC2 other",
  "Amazon Relational Database Service": "RDS",
  "Amazon Simple Storage Service": "S3",
  "Amazon Elastic Container Service": "ECS",
  "Amazon Elastic Container Service for Kubernetes": "EKS",
  "Amazon Elastic Kubernetes Service": "EKS",
  "Amazon Virtual Private Cloud": "VPC",
  "Amazon DynamoDB": "DynamoDB",
  "Amazon CloudFront": "CloudFront",
  "Amazon CloudWatch": "CloudWatch",
  "AmazonCloudWatch": "CloudWatch",
  "AWS Lambda": "Lambda",
  "AWS Key Management Service": "KMS",
  "Amazon Simple Queue Service": "SQS",
  "Amazon Simple Notification Service": "SNS",
  "Amazon Bedrock": "Bedrock",
  "Amazon Elastic Load Balancing": "ELB",
  "Amazon ElastiCache": "ElastiCache",
  "Amazon OpenSearch Service": "OpenSearch",
  "Amazon Route 53": "Route 53",
  "AWS Config": "Config",
  "Amazon GuardDuty": "GuardDuty",
  "AWS Secrets Manager": "Secrets Manager",
  "Amazon API Gateway": "API Gateway",
  "Amazon Athena": "Athena",
  "AWS Glue": "Glue",
  "Amazon Kinesis": "Kinesis",
  "Amazon Elastic File System": "EFS",
  "Amazon EC2 Container Registry (ECR)": "ECR",
};

export function awsServiceLabel(name) {
  return AWS_SHORT[name] ?? String(name).replace(/^(Amazon|AWS)\s+/, "");
}
