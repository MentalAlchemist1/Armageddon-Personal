# Lab 2B — Written Deliverables

---

## Deliverable B: Short Answers

### Q1: "What is my cache key for /api/* and why?"

**For the default `/api/*` behavior**, the cache key is essentially nothing — because caching is **disabled** (all TTLs = 0). CloudFront never stores a cached copy; every request goes straight to the origin (ALB → EC2 → Flask).

**For the `/api/public-feed` behavior**, the cache key is determined by the **AWS-managed `UseOriginCacheControlHeaders` policy** (ID: `83da9c7e-98b4-4e11-a168-04f0df8e2c65`). This means the origin (Flask) decides what gets cached and for how long via its `Cache-Control` response header. The cache key includes only the URL path — no cookies, no query strings, no extra headers.

**Why this matters:**

Think of a cache key like a label on a storage box. If you put too many things on the label (User-Agent, cookies, query strings), you end up with thousands of boxes that each hold the same thing — that's **cache fragmentation**, and it destroys your hit ratio. If you put too few things on the label, you might hand User A a box that contains User B's private data — that's a **cache poisoning incident**.

For APIs, the safest default is: don't cache at all (TTL=0), or let the origin decide (`UseOriginCacheControlHeaders`). That way, the application developer — who knows which responses are safe to share — controls the caching, not the CDN operator.

---

### Q2: "What am I forwarding to origin and why?"

**API Origin Request Policy (`chewbacca-orp-api`) forwards:**

| What | Setting | Why |
|------|---------|-----|
| Headers | `Host`, `Origin`, `Accept`, `Content-Type` | `Host` lets the ALB route by hostname. `Origin` is needed for CORS. `Accept` and `Content-Type` let the API do content negotiation. |
| Cookies | All | APIs may need session cookies or auth tokens to identify the user. |
| Query strings | All | APIs use query params for filtering, pagination, etc. (`/api/list?page=2&limit=10`). |

**Static Origin Request Policy (`chewbacca-orp-static`) forwards:**

| What | Setting | Why |
|------|---------|-----|
| Headers | `Host` only | ALB needs `Host` to route the request. Nothing else matters for a static file. |
| Cookies | None | Static files don't need cookies — a CSS file is the same for everyone. |
| Query strings | None | Static files are the same regardless of query params. Ignoring them improves cache hit ratio. |

**ELI10 Analogy:**

Imagine you're ordering pizza delivery. The API request is like a custom order — you need to forward *everything*: your name, address, toppings, allergies, payment method. The static file request is like picking up a menu from the counter — all the delivery driver needs is the restaurant address (`Host`). Forwarding your full life story to grab a menu is wasteful and slows things down.

**Key insight:** The Origin Request Policy controls what reaches your server. The Cache Policy controls what CloudFront uses to decide "is this the same request I already have stored?" They're **independent knobs**, and confusing them causes real production incidents.

---

## Deliverable B (Honors): Origin-Driven Caching

### Q3: "Why is origin-driven caching safer for APIs?"

Origin-driven caching (`UseOriginCacheControlHeaders`) is safer because **the application developer decides what's cacheable, not the infrastructure operator.**

With a fixed CDN-side cache policy (like `Managed-CachingOptimized`), CloudFront applies the same aggressive caching rules to everything — it doesn't know that `/api/list` returns different data per user, or that `/api/admin/settings` contains sensitive configuration. It just sees a response and caches it for 24 hours.

With origin-driven caching, the Flask application sends:
- `Cache-Control: public, max-age=30` on `/api/public-feed` → safe to cache for 30 seconds
- `Cache-Control: no-store, private` on `/api/user/profile` → never cache this
- No `Cache-Control` header at all → CloudFront doesn't cache (safe default)

**When would you still disable caching entirely?**

- When the API handles authentication/authorization and you can't risk serving User A's response to User B
- During development, when you need to see changes immediately
- When the API response changes on every request (real-time data, personalized content)
- When the origin application doesn't set proper `Cache-Control` headers yet (as we saw — Flask defaults to `no-cache` for static files)

**ELI10 Analogy:**

Imagine a school cafeteria. Origin-driven caching is like letting the chef put a sticky note on each dish: "This salad is good for 4 hours" or "This sushi — eat NOW, don't save it." CDN-side caching is like the cafeteria manager saying "keep everything for 24 hours" without asking the chef. The chef knows which food spoils fast. Always trust the chef.

---

## Deliverable C: Haiku (漢字で、英語なし)

> 毛深き勇者  
> 吠えれば星も震える  
> 忠義の心

**Translation for reference (not part of deliverable):**

> The furry hero  
> When he roars, even stars tremble  
> A heart of loyalty

---

## Evidence Summary

All CLI verification commands completed with results:

| Test | Result | Status |
|------|--------|--------|
| Static caching (`/static/example.txt`) | 200 OK, `cache-control: public, max-age=86400, immutable` | ✅ Policy applied correctly |
| API no-cache (`/list`) | `Miss from cloudfront` both times, no `Age` header | ✅ Dynamic routes never cached |
| Query string sanity (`?v=1` vs `?v=2`) | Same etag, same content-length | ✅ Query strings ignored for static |
| Managed origin-driven policy | `83da9c7e-98b4-4e11-a168-04f0df8e2c65` on `/api/public-feed` | ✅ Correct policy attached |
| Origin cloaking (direct ALB) | Connection timeout | ✅ ALB unreachable directly |
| WAF on CloudFront | `chewbacca-cf-waf` ARN returned | ✅ WAF attached |
| ALB SG | No `0.0.0.0/0`, CloudFront prefix list only | ✅ Locked down |
| AAAA record | Created, points to CloudFront | ✅ IPv6 enabled |
| CloudFront logging | S3 bucket `chewbacca-cf-logs-262164343754` | ✅ Enabled |

---

*Note: Static cache `x-cache: Miss` on repeated requests is expected behavior — Flask origin sends `Cache-Control: no-cache` which overrides CDN-side `min_ttl` for revalidation. The response headers policy correctly applies `public, max-age=86400, immutable` to the viewer-facing response, instructing browsers to cache locally for 24 hours.*
