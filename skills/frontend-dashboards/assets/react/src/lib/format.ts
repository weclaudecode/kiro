// Number and date formatting. Intl formatters are expensive to construct - build once, reuse.
// Same behavior as assets/vanilla/js/format.js.

const LOCALE: string | undefined = undefined; // viewer's locale; pin (e.g. "en-US") for stable screenshots

const cache = new Map<string, Intl.NumberFormat | Intl.DateTimeFormat>();
function fmt<T extends Intl.NumberFormat | Intl.DateTimeFormat>(key: string, factory: () => T): T {
  let f = cache.get(key) as T | undefined;
  if (!f) {
    f = factory();
    cache.set(key, f);
  }
  return f;
}

export function currency(value: number, code = "USD", opts: { compact?: boolean; decimals?: number } = {}): string {
  const { compact = false } = opts;
  const abs = Math.abs(value);
  const digits = opts.decimals ?? (compact ? (abs >= 1000 ? 1 : 0) : abs >= 1000 ? 0 : 2);
  return fmt(
    `cur:${code}:${compact}:${digits}`,
    () =>
      new Intl.NumberFormat(LOCALE, {
        style: "currency",
        currency: code,
        notation: compact ? "compact" : "standard",
        minimumFractionDigits: compact ? 0 : digits,
        maximumFractionDigits: digits,
      }),
  ).format(value);
}

export function percent(ratio: number, decimals = 1): string {
  return fmt(
    `pct:${decimals}`,
    () => new Intl.NumberFormat(LOCALE, { style: "percent", minimumFractionDigits: decimals, maximumFractionDigits: decimals }),
  ).format(ratio);
}

export type Direction = "up" | "down" | "flat";

export function delta(current: number, previous: number | null): { text: string; dir: Direction } | null {
  if (!previous) return null;
  const pct = (current - previous) / previous;
  const dir: Direction = Math.abs(pct) < 0.005 ? "flat" : pct > 0 ? "up" : "down";
  const arrow = dir === "up" ? "▲" : dir === "down" ? "▼" : "–";
  const sign = pct > 0 ? "+" : pct < 0 ? "−" : "";
  return { text: `${arrow} ${sign}${percent(Math.abs(pct))}`, dir };
}

// Dates are ISO "YYYY-MM-DD" strings end to end. Parse as UTC so no timezone shifts a day.
export const parseDay = (iso: string): Date => new Date(`${iso}T00:00:00Z`);
export const toDay = (d: Date): string => d.toISOString().slice(0, 10);

export function addDays(iso: string, n: number): string {
  const d = parseDay(iso);
  d.setUTCDate(d.getUTCDate() + n);
  return toDay(d);
}

export const daysBetween = (start: string, end: string): number =>
  Math.round((parseDay(end).getTime() - parseDay(start).getTime()) / 86_400_000) + 1;

export const shortDate = (iso: string): string =>
  fmt("d:short", () => new Intl.DateTimeFormat(LOCALE, { month: "short", day: "numeric", timeZone: "UTC" })).format(parseDay(iso));

export const longDate = (iso: string): string =>
  fmt("d:long", () => new Intl.DateTimeFormat(LOCALE, { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" })).format(
    parseDay(iso),
  );

export const monthName = (iso: string): string =>
  fmt("d:month", () => new Intl.DateTimeFormat(LOCALE, { month: "long", timeZone: "UTC" })).format(parseDay(iso));

// AWS billing names are long. Short labels for axes/legends/KPIs; full names in tooltips, table, CSV.
const AWS_SHORT: Record<string, string> = {
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
  AmazonCloudWatch: "CloudWatch",
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

export const awsServiceLabel = (name: string): string => AWS_SHORT[name] ?? name.replace(/^(Amazon|AWS)\s+/, "");
