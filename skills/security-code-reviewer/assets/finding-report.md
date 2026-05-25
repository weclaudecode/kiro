# Finding Report Template

One finding per issue. Group only when findings share a single root cause
and a single fix. Severity is assigned via `severity-rubric.md`.

---

## Finding: <short, specific title>

- **Severity:** <Critical | High | Medium | Low | Informational>
- **CWE/OWASP:** <e.g. CWE-89 (SQL Injection) / OWASP A03:2021>
- **Location:** `<path/to/file.ext:LINE-LINE>`

### Vulnerable Code

```<language>
<paste the vulnerable snippet, with surrounding context if needed>
```

### Impact

<What an attacker can do, concretely. Name the data, the path, the payload,
the rows or accounts affected. Avoid hedging language ("may lead to",
"could possibly"). State what happens.>

### Reproduction

```bash
<exact curl, payload, or test snippet that demonstrates the issue>
```

<Expected attacker-observable outcome — e.g. "returns 14,302 rows instead
of the caller's 3", or "responds 200 with the contents of
/etc/passwd".>

### Remediation

<The fix, in prose first if non-obvious, then a corrected code snippet.
Address the root cause, not the symptom. If the fix has trade-offs (e.g.
a perf cost), state them.>

```<language>
<corrected code>
```

### References

- <CWE link>
- <CVE if applicable>
- <Vendor advisory or OWASP cheat sheet>

---

# Worked Example

## Finding: SQL injection in `OrderRepository.find_by_user`

- **Severity:** High
- **CWE/OWASP:** CWE-89 / OWASP A03:2021 — Injection
- **Location:** `services/orders/repository.py:42-48`

### Vulnerable Code

```python
def find_by_user(user_id: str):
    query = f"SELECT * FROM orders WHERE user_id = '{user_id}'"
    return db.execute(query).fetchall()
```

### Impact

An authenticated attacker can read every row in the `orders` table,
including other users' billing addresses and order totals, by sending
`user_id=' OR '1'='1` to `GET /api/orders`. The endpoint enforces login but
not row-level ownership, so the SQL injection bypasses the only access
check.

### Reproduction

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.example.com/api/orders?user_id=%27%20OR%20%271%27%3D%271"
```

Returns 14,302 rows instead of the caller's 3.

### Remediation

Use a parameterized query. Do not interpolate user input into the SQL
string under any circumstances. Additionally, enforce that `user_id`
matches the authenticated principal at the controller layer (see related
finding on broken access control).

```python
def find_by_user(user_id: str):
    query = "SELECT * FROM orders WHERE user_id = %s"
    return db.execute(query, (user_id,)).fetchall()
```

### References

- CWE-89: https://cwe.mitre.org/data/definitions/89.html
- OWASP SQL Injection Prevention Cheat Sheet
