# Week 3 — MySQL → T-SQL Migration on Microsoft Fabric

## TL;DR

Re-implemented the entire Week 2 mart in Microsoft Fabric Warehouse using
T-SQL. The deliverable is two parallel SQL trees — `sql/schema/` (MySQL) and
`sql/fabric/schema/` (T-SQL on Fabric) — that produce the same 2,142-row mart
on both engines, plus a migration cheat sheet documenting every dialect
difference I hit.

The point of this week was not the migration per se — it was demonstrating
fluency across two SQL dialects and one cloud platform.

---

## Lesson 1: JSON, dates, and regex are where the dialect war is fought

The migration was 90% mechanical and 10% genuinely tricky. The 10% lived in
three areas.

### JSON: usually cleaner in T-SQL, except where it isn't

| MySQL | T-SQL on Fabric |
|---|---|
| `JSON_UNQUOTE(JSON_EXTRACT(x, '$.path'))` | `JSON_VALUE(x, '$.path')` |
| `JSON_ARRAYAGG(col)` | Manual: `'[' + STRING_AGG('"' + col + '"', ',') + ']'` (no built-in equivalent, and no escaping help) |
| `JSON_LENGTH(arr)` + dynamic path build | No `JSON_LENGTH`. I used reverse `COALESCE` from the deepest expected level back to find the first non-null. |

The dynamic last-element-of-array pattern was the most painful to rewrite. The
two implementations end up functionally equivalent but read very differently.

### Dates: every function renamed, parameters reordered

```
CURDATE()                    → CAST(GETDATE() AS DATE)
QUARTER(d)                   → DATEPART(QUARTER, d)
MONTHNAME(d) / DAYNAME(d)    → DATENAME(MONTH, d) / DATENAME(WEEKDAY, d)
DATE_FORMAT(d, '%Y%m%d')     → CONVERT(VARCHAR(8), d, 112)
DATEDIFF(end, start)         → DATEDIFF(DAY, start, end)     ← order reversed, unit required
```

The `DATEDIFF` trap is silent: same function name, opposite argument order, and
T-SQL requires an explicit unit. Compiles fine, returns the wrong number. Easy
to miss in code review.

### Regex: just gone

Fabric Warehouse has no `REGEXP` / `REGEXP_LIKE` (that's Fabric SQL Database,
a different product). Word-boundary matching becomes:

```sql
PATINDEX('%[^a-zA-Z0-9]word[^a-zA-Z0-9]%', ' ' + x + ' ') > 0
```

That works but is not maintainable as a *family* of skill keywords. There's
also no `REGEXP_REPLACE`, so collapsing whitespace becomes a chain of
`REPLACE` calls. I documented these in the migration doc as known-degraded
features rather than rewriting around them.

### Smaller surprises

- `SUM(boolean)` doesn't compile — T-SQL booleans aren't first-class values.
  Use `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` or `COUNT(col)` for non-null
  counting.
- `LEAST` / `GREATEST` are missing for value swapping, but T-SQL's
  `UPDATE ... SET a = b, b = a` form is cleaner anyway.

---

## Lesson 2: Fabric Warehouse is T-SQL with the safety rails removed

Fabric Warehouse is a Massively Parallel Processing (MPP) engine — like
Synapse or Snowflake — not classic SQL Server. The DDL surface has been
narrowed substantially, and some of the cuts caught me off-guard.

### What's gone from `CREATE TABLE`

- **`DEFAULT` values** — not in CREATE, not in ALTER. Defaults are handled at
  INSERT time.
- **Inline constraints** — no inline `PRIMARY KEY`, `UNIQUE`, or `FOREIGN
  KEY`. They must be added as separate `ALTER TABLE ... ADD CONSTRAINT ...
  NONCLUSTERED NOT ENFORCED` (FK needs `NOT ENFORCED` only).
- **`CHECK` constraints** — not supported.
- **`TINYINT`** — use `SMALLINT`.
- **`DATETIME2`** requires explicit precision, max 6 (so `DATETIME2(6)` not
  the implicit `DATETIME2(7)` of classic T-SQL).

### Indexes work differently

You can't `CREATE INDEX`. There are no B-tree secondary indexes — the
columnstore engine handles everything internally. My instinct was "this will
be slow," but at 2,142 rows query latency was zero. The engine clearly does a
lot of work I don't see.

### `NOT ENFORCED` still has consequences

Foreign keys marked `NOT ENFORCED` will still block a `TRUNCATE` on the
referenced table. I assumed `NOT ENFORCED` meant "documentation only" and
spent a while debugging why TRUNCATE failed. Switched to `DELETE FROM` and
moved on. This is poorly documented and worth knowing.

### The `#temp` table distribution trap

This was the most genuinely-new concept of the week. In an MPP engine,
**every table needs to know how its rows are distributed across compute
nodes.** Permanent tables get an automatic round-robin distribution. `#temp`
tables don't — they default to a single-node MDF backing, and the moment you
JOIN them against a distributed permanent table the engine throws "object not
supported in distributed processing mode."

Fix:

```sql
CREATE TABLE #stage_xyz (...) WITH (DISTRIBUTION = ROUND_ROBIN);
```

This concept simply doesn't exist in MySQL. Single-node engines don't need to
think about it.

---

## Lesson 3: Verify the bridge before you build the building

Before writing any of the heavy migration code, I spent 5 minutes confirming
that my Fabric Warehouse could even read the Lakehouse-mounted source:

```sql
SELECT COUNT(*) FROM [adzuna_bronze].[dbo].[raw_jobs];
-- 2,622 — same as MySQL source
```

If cross-database access had failed, every subsequent T-SQL file would have
been wasted work. This is the kind of de-risking move that costs almost
nothing and saves hours. **First test the cheapest part of the riskiest
assumption.**

---

## Lesson 4: When you hit a dialect quirk, write it down on the spot

I kept a running notes file as I migrated. Every time I tripped over
something (DEFAULT not supported, TINYINT rejected, DATEDIFF reversed, etc.)
I added a row to a table immediately, while the friction was fresh.

By the end of the week that file was `docs/migration-mysql-to-fabric-
warehouse.md` — a proper cheat sheet covering every dialect difference,
indexed by feature. It is now a portfolio asset in its own right, not just
my personal scratchpad.

The two-tree repo structure (`sql/schema/` and `sql/fabric/schema/` with
mirrored filenames) makes the migration auditable: a reviewer can open any
file in both trees side by side and see the exact translation. That's
something a single "I migrated it to Fabric" sentence cannot convey.

---

## What I would do differently

Nothing structural — but I would budget more time upfront for the `#temp`
distribution gotcha. It's the kind of thing that has no obvious tell until
you trip over it, and the error message doesn't immediately suggest the cause.
Future-me would know to add `WITH (DISTRIBUTION = ROUND_ROBIN)` reflexively
to every `#temp CREATE TABLE` in Fabric.
