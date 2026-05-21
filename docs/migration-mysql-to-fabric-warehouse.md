# MySQL → Fabric Warehouse Migration Cheat Sheet

Quick-reference notes for porting MySQL ETL scripts to Microsoft Fabric Data Warehouse (T-SQL).
Compiled while migrating the Adzuna Job Market Pipeline (2,142 rows, 7-table star schema) end-to-end.

---

## 1. CREATE TABLE — Fabric Warehouse rules

| MySQL                                                     | Fabric Warehouse                                                                     | Why                                                                 |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| `col TYPE DEFAULT value`                                  | Remove `DEFAULT`; set value at INSERT time                                           | DEFAULT constraints not supported (CREATE or ALTER)                 |
| `col TYPE PRIMARY KEY` (inline)                           | Move to `ALTER TABLE … ADD CONSTRAINT … PRIMARY KEY NONCLUSTERED (col) NOT ENFORCED` | Keys cannot be declared inline; must be `NONCLUSTERED NOT ENFORCED` |
| `UNIQUE KEY name (col)`                                   | `ALTER TABLE … ADD CONSTRAINT … UNIQUE NONCLUSTERED (col) NOT ENFORCED`              | Same as PK                                                          |
| `FOREIGN KEY … REFERENCES …` (inline)                     | `ALTER TABLE … ADD CONSTRAINT … FOREIGN KEY (col) REFERENCES … NOT ENFORCED`         | FK needs only `NOT ENFORCED` (no `NONCLUSTERED`)                    |
| `TINYINT`                                                 | `SMALLINT`                                                                           | TINYINT not in Fabric's supported type set                          |
| `DATETIME`                                                | `DATETIME2(6)`                                                                       | Precision required (0–6, max 6)                                     |
| `TEXT`, `JSON`                                            | `VARCHAR(MAX)`                                                                       | No native TEXT/JSON types                                           |
| `INDEX idx_x (col)` (inline)                              | Remove                                                                               | Columnstore indexes data automatically                              |
| `CHECK (…)`                                               | Remove                                                                               | Not supported                                                       |
| `ENGINE=`, `CHARSET=`, `COLLATE=`, table-level `COMMENT=` | Remove                                                                               | MySQL-only                                                          |
| Column-inline `COMMENT 'x'`                               | Move to `-- x` above the column                                                      | T-SQL has no inline column comments                                 |
| `AUTO_INCREMENT`                                          | `BIGINT IDENTITY` (inline OK; bigint only, no SEED/INCREMENT)                        | Standard Fabric replacement                                         |

**Gotcha:** FK constraints, even `NOT ENFORCED`, **block `TRUNCATE` on the referenced parent table at metadata level**. Use `DELETE FROM` instead.

---

## 2. DML translation patterns

### JSON

| MySQL                                         | T-SQL (Fabric)                                      |
| --------------------------------------------- | --------------------------------------------------- |
| `JSON_UNQUOTE(JSON_EXTRACT(x, '$.path'))`     | `JSON_VALUE(x, '$.path')`                           |
| `JSON_ARRAYAGG(col)`                          | `'[' + STRING_AGG('"' + col + '"', ',') + ']'`      |
| `JSON_LENGTH + CONCAT` (dynamic last-element) | Reverse-COALESCE from highest known index down to 0 |

### Date / time

| MySQL                                  | T-SQL (Fabric)                                                             |
| -------------------------------------- | -------------------------------------------------------------------------- |
| `STR_TO_DATE(s, '%Y-%m-%dT%H:%i:%sZ')` | `TRY_CAST(s AS DATETIME2(6))` — T-SQL parses ISO-8601 natively             |
| `CURDATE()`                            | `CAST(GETDATE() AS DATE)`                                                  |
| `CURRENT_TIMESTAMP` as default         | Set `SYSUTCDATETIME()` explicitly at INSERT                                |
| `DATEDIFF(end, start)`                 | `DATEDIFF(DAY, start, end)` — **unit required + args swapped**             |
| `DATE_FORMAT(d, '%Y%m%d')`             | `CONVERT(VARCHAR(8), d, 112)` (style 112 = `yyyyMMdd`)                     |
| `QUARTER(d)`                           | `DATEPART(QUARTER, d)`                                                     |
| `MONTHNAME(d)` / `DAYNAME(d)`          | `DATENAME(MONTH, d)` / `DATENAME(WEEKDAY, d)`                              |
| `DAYOFMONTH(d)`                        | `DAY(d)`                                                                   |
| `WEEKDAY(d) + 1` (1=Mon..7=Sun)        | `CASE DATENAME(WEEKDAY, d) WHEN 'Monday' THEN 1 …` (DATEFIRST-independent) |

### Strings / regex

| MySQL                                   | T-SQL (Fabric)                                                                                       |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `CHAR_LENGTH(x)`                        | `LEN(x)`                                                                                             |
| `TRIM(x)`                               | `LTRIM(RTRIM(x))`                                                                                    |
| `REGEXP_REPLACE(x, '\s+', ' ')`         | **No regex.** Chain `REPLACE` for `CHAR(13)/(10)/(9)` + trim. True multi-space collapse unavailable. |
| `x REGEXP '\\bword\\b'` (word boundary) | `PATINDEX('%[^a-zA-Z0-9]word[^a-zA-Z0-9]%', ' ' + x + ' ') > 0`                                      |
| `CONCAT_WS(sep, a, b, c)`               | Same (T-SQL 2017+, supported in Fabric)                                                              |

### Boolean / aggregation

| MySQL                                     | T-SQL (Fabric)                                                             |
| ----------------------------------------- | -------------------------------------------------------------------------- |
| `SUM(col IS NOT NULL)`                    | `COUNT(col)`                                                               |
| `SUM(col IS NULL)`                        | `COUNT(*) - COUNT(col)`                                                    |
| `SUM(condition)`                          | `SUM(CASE WHEN condition THEN 1 ELSE 0 END)` — booleans aren't first-class |
| `LEAST(a, b)` / `GREATEST(a, b)` for swap | T-SQL swap idiom: `SET a = b, b = a` (right-hand uses OLD row values)      |
| `CAST(x AS UNSIGNED)`                     | `CAST(x AS INT)` or `SMALLINT`                                             |

### Control flow / misc

| MySQL                                              | T-SQL (Fabric)                                                             |
| -------------------------------------------------- | -------------------------------------------------------------------------- |
| `USE database;`                                    | Remove — Warehouse context is connection-level                             |
| `SET FOREIGN_KEY_CHECKS = 0/1`                     | Remove — FKs are NOT ENFORCED anyway                                       |
| `TRUNCATE TABLE x` (when x is FK-referenced)       | `DELETE FROM x`                                                            |
| `INSERT INTO x (...) WITH cte AS (...) SELECT ...` | `WITH cte AS (...) INSERT INTO x (...) SELECT ...` — **CTE before INSERT** |
| `FROM dual`                                        | Remove — T-SQL doesn't need FROM for scalar SELECT                         |
| `PREPARE … EXECUTE` dynamic SQL                    | Refactor to static, or use `EXEC sp_executesql`                            |
| `ALTER TABLE … ADD COLUMN c TYPE AFTER y`          | No `AFTER` in T-SQL; columns always added at the end                       |

---

## 3. Fabric Warehouse architectural specifics

| Topic                       | What to know                                                                                                                                                                                                                        |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cross-DB query**          | Warehouse reads Lakehouse tables via 3-part naming: `[lakehouse].[dbo].[table]`. Same OneLake storage, different engine — zero data movement. Lakehouse SQL endpoint is read-only.                                                  |
| **Distributed temp tables** | `#temp` tables are non-distributed by default. JOINing them with persisted (distributed) tables fails with _"object not supported in distributed processing mode"_. Fix: declare `WITH (DISTRIBUTION = ROUND_ROBIN)` on the CREATE. |
| **Collation**               | Default is case-insensitive UTF-8; `LIKE` / `PATINDEX` are case-blind without explicit `LOWER()`.                                                                                                                                   |
| **IDENTITY behaviour**      | Inline `BIGINT IDENTITY` works. No SEED/INCREMENT customisation. `DELETE` doesn't reset the counter (TRUNCATE would, but TRUNCATE is blocked by FKs). Counter growth across reloads is cosmetic — natural-key joins still match.    |

---

## 4. Parity verification (Adzuna pipeline, 8-table check)

7 of 8 tables matched MySQL exactly. `dim_company` differs by +1 (812 vs 811, +0.12%), traced to subtle unicode-whitespace handling differences between MySQL `TRIM()` and T-SQL `LTRIM(RTRIM())`. No functional impact on analytics; documented as a known dialect-level edge case.
