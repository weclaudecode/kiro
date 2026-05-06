# Application Flaw Classes

Each section below names the sinks to look for, the indicators of a
vulnerability, and the fix. Vulnerable and fixed pairs are shown in Python,
JavaScript/TypeScript, Java, and Go where the patterns differ meaningfully.

## Injection

### SQL

The reviewer looks for f-strings, `.format()`, `%`-formatting, or `+`
concatenation into a query string.

```python
# Vulnerable
cursor.execute(f"SELECT * FROM users WHERE name = '{name}'")

# Fixed
cursor.execute("SELECT * FROM users WHERE name = %s", (name,))
```

```javascript
// Vulnerable
db.query(`SELECT * FROM users WHERE id = ${req.params.id}`);

// Fixed
db.query("SELECT * FROM users WHERE id = $1", [req.params.id]);
```

```java
// Vulnerable
String q = "SELECT * FROM users WHERE name = '" + name + "'";
stmt.executeQuery(q);

// Fixed
PreparedStatement ps = conn.prepareStatement(
    "SELECT * FROM users WHERE name = ?");
ps.setString(1, name);
ps.executeQuery();
```

```go
// Vulnerable
db.Query(fmt.Sprintf("SELECT * FROM users WHERE name = '%s'", name))

// Fixed
db.Query("SELECT * FROM users WHERE name = $1", name)
```

ORMs are not immune — `Model.objects.raw(f"...")`, Sequelize
`literal(userInput)`, and Hibernate `createQuery(String)` with concatenation
all reintroduce the flaw.

### NoSQL

MongoDB operator injection occurs when an object body is passed straight
into a query: `User.find(req.body)`. An attacker sends
`{"username":{"$ne": null}, "password":{"$ne": null}}` to bypass auth. The
reviewer looks for `$where`, `$function`, and any unfiltered object spread
into a query.

### Command Injection

Sinks: `os.system`, `subprocess.run(..., shell=True)`,
`subprocess.Popen(..., shell=True)`, Node `child_process.exec` (vs
`execFile`), Java `Runtime.exec(String)` with concatenation, Go
`exec.Command("sh", "-c", ...)`.

```python
# Vulnerable
subprocess.run(f"convert {filename} out.png", shell=True)

# Fixed
subprocess.run(["convert", filename, "out.png"], shell=False)
```

```javascript
// Vulnerable
child_process.exec(`convert ${filename} out.png`);

// Fixed
child_process.execFile("convert", [filename, "out.png"]);
```

```go
// Vulnerable
exec.Command("sh", "-c", "convert "+filename+" out.png").Run()

// Fixed
exec.Command("convert", filename, "out.png").Run()
```

### LDAP, XPath

Same principle: parameterize, escape with library helpers, do not concatenate.

### Template Injection

`Environment(loader=...).from_string(user_input)` in Jinja2 is RCE. So is
rendering user input as a template body in Twig, Velocity, Freemarker, ERB,
or Handlebars-with-helpers. The fix is to never compile user input as a
template — pass it as data only.

## SSRF

Any HTTP client called with a URL derived from user input is suspect:
`requests.get(url)`, `fetch(url)`, `axios.get(url)`, `httpx`, `urllib`,
`net/http`, `HttpClient`. The reviewer specifically checks:

- Is there a URL allowlist? (Allowlist beats blocklist — IP encodings,
  redirects, and DNS rebinding defeat blocklists.)
- Is the cloud metadata service blocked? (`169.254.169.254`,
  `fd00:ec2::254`, GCP `metadata.google.internal`, Azure `169.254.169.254`)
- Are redirects followed? A whitelisted domain can redirect to internal IPs
  unless `allow_redirects=False`.
- Is the `file://` scheme accepted? (Local file read.)

```python
# Vulnerable
def fetch_image(url):
    return requests.get(url).content

# Fixed (allowlist + scheme check + no redirects)
ALLOWED_HOSTS = {"images.example.com", "cdn.example.com"}
def fetch_image(url):
    p = urlparse(url)
    if p.scheme not in ("https",) or p.hostname not in ALLOWED_HOSTS:
        raise ValueError("disallowed URL")
    return requests.get(url, allow_redirects=False, timeout=5).content
```

```javascript
// Vulnerable
const data = await axios.get(req.body.url);

// Fixed
const ALLOWED = new Set(["images.example.com", "cdn.example.com"]);
const u = new URL(req.body.url);
if (u.protocol !== "https:" || !ALLOWED.has(u.hostname)) {
  throw new Error("disallowed URL");
}
const data = await axios.get(u.toString(), {
  maxRedirects: 0,
  timeout: 5000,
});
```

## Deserialization

Treat as RCE primitives unless proven otherwise:

- Python: `pickle.loads`, `cPickle.loads`, `marshal.loads`, `yaml.load`
  (must be `yaml.safe_load`), `shelve` of attacker data
- Java: `ObjectInputStream.readObject`, `XMLDecoder`, Jackson with
  default-typing, SnakeYAML default constructor
- .NET: `BinaryFormatter`, `SoapFormatter`, `LosFormatter`,
  `NetDataContractSerializer`, `JavaScriptSerializer` with type resolver
- PHP: `unserialize`, `phar://` stream wrapper
- Ruby: `Marshal.load`, YAML with `Psych.unsafe_load`

The fix is always: do not deserialize attacker-controlled data with these
primitives. Use JSON with explicit schemas (Pydantic, Zod, Jackson with
strict typing).

```python
# Vulnerable
import yaml
config = yaml.load(user_input)

# Fixed
import yaml
config = yaml.safe_load(user_input)
```

```java
// Vulnerable
ObjectInputStream ois = new ObjectInputStream(req.getInputStream());
Object obj = ois.readObject();

// Fixed — parse JSON with a fixed schema
ObjectMapper m = new ObjectMapper();
m.disable(MapperFeature.DEFAULT_VIEW_INCLUSION);
MyDto dto = m.readValue(req.getInputStream(), MyDto.class);
```

## Authentication and Session

Common flaws:

- **JWT signature not verified.** `jwt.decode(token, options={"verify_signature": False})`
  in PyJWT, `jwt.verify` not called in jsonwebtoken, custom split-and-base64
  parsing.
- **`alg: none` accepted.** Library does not pin algorithms — pass
  `algorithms=["RS256"]` (or HS256, but be deliberate). Never accept
  `none`.
- **Hardcoded JWT secret.** `SECRET = "change-me"` committed to the repo.
- **Weak randomness for tokens.** `Math.random()`, `random.random()`,
  `rand()`, `new Random()` for session IDs, password reset tokens, CSRF
  tokens, invite codes. Use `secrets.token_urlsafe`, `crypto.randomBytes`,
  `SecureRandom`, `crypto/rand`.
- **Session fixation.** Session ID not rotated on login.
- **Cookie flags missing.** `HttpOnly`, `Secure`, `SameSite=Lax|Strict`.
- **Password storage.** MD5, SHA1, SHA256, even salted, are wrong. Use
  bcrypt (cost ≥ 12), argon2id, or scrypt.

```python
# Vulnerable — weak token, predictable
import random
token = str(random.random())[2:]

# Fixed
import secrets
token = secrets.token_urlsafe(32)
```

```javascript
// Vulnerable — alg: none accepted
const payload = jwt.verify(token, secret);

// Fixed — pin the algorithm
const payload = jwt.verify(token, secret, { algorithms: ["RS256"] });
```

```go
// Vulnerable — weak randomness
import "math/rand"
n := rand.Int63()

// Fixed
import "crypto/rand"
b := make([]byte, 32)
_, _ = rand.Read(b)
```

## Authorization

- **IDOR.** Object IDs in URLs (`/orders/12345`) without an ownership check.
  The fix is `WHERE order_id = ? AND user_id = ?`, not just
  `WHERE order_id = ?`.
- **Missing `@authorize` checks.** A handler exists but no decorator/guard
  runs. In Spring, the reviewer looks for controllers without
  `@PreAuthorize`. In Django REST Framework, for views with no
  `permission_classes`.
- **Multi-tenant bleed-through.** Shared connection pool, shared cache key,
  request-scoped tenant ID set from a header rather than the auth token.
- **Forced browsing.** Admin endpoints reachable without admin role check.

```python
# Vulnerable — IDOR
@app.get("/orders/<order_id>")
def get_order(order_id):
    return Order.query.get(order_id)

# Fixed — bind to authenticated user
@app.get("/orders/<order_id>")
@login_required
def get_order(order_id):
    return Order.query.filter_by(
        id=order_id, user_id=current_user.id
    ).first_or_404()
```

## XSS / Output Encoding

- Server templates with explicit unescape: Jinja2 `{{ value | safe }}`,
  Django `{% autoescape off %}`, ERB `<%== %>`.
- React `dangerouslySetInnerHTML={{__html: userInput}}`.
- Vanilla `element.innerHTML = userInput` or `document.write(userInput)`.
- jQuery `$(el).html(userInput)`.
- Returning user input as `Content-Type: text/html` from an API.

The fix is contextual escaping (HTML-attribute, JS, URL, CSS contexts each
need different encoding) plus a strict CSP as defense-in-depth.

## CSRF

- State-changing GET requests (any GET that mutates server state).
- Cookie-authenticated POST/PUT/DELETE without a CSRF token, double-submit
  cookie, or `SameSite=Lax|Strict` on the auth cookie.
- SPAs that send `Authorization: Bearer ...` from `localStorage` are not
  CSRF-vulnerable in the classic sense but are XSS-leakable — note that
  trade-off.

## TOCTOU

- Filesystem: `os.path.exists(p)` then `open(p)` — symlink swapped between
  the two. Use `O_NOFOLLOW` and operate on file descriptors.
- Database: `SELECT balance` then `UPDATE balance = balance - amount`
  without a transaction or `SELECT ... FOR UPDATE`. Race condition lets a
  user spend the same balance twice.
- Idempotency keys checked then written without an atomic primitive.

```python
# Vulnerable
row = db.execute("SELECT balance FROM accounts WHERE id=%s", (id,)).fetchone()
if row.balance >= amount:
    db.execute(
        "UPDATE accounts SET balance = balance - %s WHERE id=%s",
        (amount, id),
    )

# Fixed — single atomic statement
res = db.execute(
    "UPDATE accounts SET balance = balance - %s "
    "WHERE id=%s AND balance >= %s",
    (amount, id, amount),
)
if res.rowcount == 0:
    raise InsufficientFunds()
```

## Secrets

- Hardcoded API keys, DB passwords, JWT secrets, signing keys.
- Secrets in default values
  (`DATABASE_URL = os.getenv("DATABASE_URL", "postgres://prod:realpass@...")`).
- Secrets in logs (`logger.info(f"Auth header: {request.headers}")`).
- Secrets in error messages returned to the client.
- Secrets in client-side bundles (`process.env.SECRET_KEY` in Next.js
  without the `NEXT_PUBLIC_` prefix is a footgun the other way — but
  the reviewer checks Webpack/Vite configs for `define` blocks that bake
  server secrets into the bundle).
- Secrets in git history even after the file was rewritten.
