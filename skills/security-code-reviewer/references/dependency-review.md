# Dependency Review

Dependency review covers lockfile hygiene, scanner output triage, transitive
risk, abandoned packages, typosquats, and SBOM generation.

## Lockfile Present and Committed

- `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- `poetry.lock`, `Pipfile.lock`, `uv.lock`
- `Cargo.lock`
- `go.sum`
- `Gemfile.lock`
- `composer.lock`

Without a lockfile, the install is non-reproducible and a transitive
package can be swapped silently. Library projects (publishing to a registry)
typically do not commit lockfiles; application projects always should.

## Scanner Output

The reviewer runs the relevant scanner and reads the report:

| Ecosystem | Tool |
| --- | --- |
| Python | `pip-audit`, `safety` |
| Node | `npm audit`, `yarn audit`, `pnpm audit` |
| Rust | `cargo audit` |
| Ruby | `bundle audit` |
| Elixir | `mix deps.audit` |
| Go | `govulncheck` |
| Cross-language | `osv-scanner`, `trivy fs` |

## Transitive Dependencies

Direct deps may be clean while a transitive has a CVE — scanners check
both, but the reviewer verifies by reading the report and checking the
upgrade path (sometimes the only fix is to upgrade a direct dep that pins
the vulnerable transitive).

## Abandoned Packages

Indicators:

- Last release > 2 years ago
- No maintainer activity (issues / PRs unanswered)
- Open security issues unanswered
- Repository archived

The fix is to replace, fork, or vendor in.

## Typosquats

`requets` vs `requests`, `colourama` vs `colorama`, `cross-env` vs
`cross-env-shell`, `python-sqlite` vs `pysqlite3`. The reviewer diffs the
dependency list against the README'd canonical names and looks for unusual
publishers on recently-added packages.

## Supply-Chain Indicators in `package.json`

- `postinstall`, `preinstall`, `prepare` scripts in untrusted deps —
  run as the install user, often with full network access
- Newly-added dep with very few weekly downloads
- Dep maintained by a single new account

## SBOM Generation

`syft`, `cyclonedx-bom`, BuildKit `--sbom=true`. Required for any project
shipping to customers under modern compliance regimes (SOC 2, FedRAMP,
EU CRA). The SBOM is generated at build time and shipped alongside the
artifact (image, binary, package).

## CVE Triage

When a scanner reports a CVE the reviewer answers:

1. Is the vulnerable code path reachable from production?
   (`govulncheck` does this for Go; for other languages the reviewer
   checks the call sites manually.)
2. Is there a fix version? If yes, upgrade.
3. If no fix, is there a workaround (config flag, version pin to a
   pre-vuln release, removal of the dep)?
4. If none of the above, document the accepted risk with an expiry date
   and a re-check trigger.
