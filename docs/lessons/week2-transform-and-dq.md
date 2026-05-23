# Week 2 — Transform, Deduplication, and Data Quality

## TL;DR

This is the longest lesson because Week 2 is where the project's real shape
got decided. I took 2,622 raw rows and produced a star-schema mart with a fact
table, five dimensions, and a bridge — but the work that mattered most was
not the ELT plumbing. It was the *deduplication strategy*, the *data-quality
gates*, and a handful of design decisions where the obvious answer was wrong.

---

## Lesson 1: Duplicate detection is two different problems, not one

There were two kinds of duplicates to handle. They needed completely different
solutions, and conflating them is how junior DAs over-engineer this step.

### Exact duplicates: 2,622 → 2,142 (480 rows removed)

The 480-row reduction is **not** a data-quality problem. It is the natural
result of my extraction strategy: I called the Adzuna API with seven separate
search terms (`data analyst`, `data engineer`, `data scientist`, etc.), so a
job titled "Senior Data Engineer" might come back under both `data engineer`
and `data analyst` searches.

I de-duplicated on Adzuna's own `job_id` using `ROW_NUMBER() OVER (PARTITION BY
job_id ORDER BY fetched_at DESC, id DESC)`, keeping the most recently fetched
row and aggregating the search terms into a JSON array (`search_terms`) plus a
count (`search_term_count`). No information was lost — and `search_term_count
> 1` turned out to be a useful signal in its own right ("this role spans
multiple data-job definitions").

A bug worth recording: my first attempt was `GROUP BY job_id, raw_data`, but
the same `job_id` had slightly different `raw_data` JSON when fetched under
different search terms (the `search_term` field inside the payload differed),
so MySQL kept two rows per `job_id` and the downstream `PRIMARY KEY` on
`job_posting_id` blew up. The fix was to switch to `ROW_NUMBER()` with a
two-step CTE: aggregate search terms first, then pick the representative row.

### Fuzzy duplicates: a different question entirely

"Fuzzy" duplicate here does **not** mean string-similarity (`rapidfuzz`,
`fuzzywuzzy`, `SOUNDEX`). It means: **different `job_id`, same job** —
typically a recruiter re-posting the same role a few days later because the
first listing did not get traction.

I detected these with a pure SQL self-join and ran two versions side by side:

| Detector | Match condition | Result |
|---|---|---|
| Loose (Check 5) | `title_normalized` + `company_normalized` + `state` | 27.3% (584 rows flagged) |
| Tight (Check 5b) | + `suburb` exact match + `\|DATEDIFF\| ≤ 7 days` | 5.1% (110 pairs) |

The loose version's 27.3% was clearly an over-count — large employers
legitimately post multiple "Senior Data Analyst" roles in the same state for
different teams. The tight version added two constraints that make sense for
real re-postings: same suburb (different teams cluster in different offices)
and within a 7-day window (re-posts are usually a few days apart, not months).

**Why I documented but did not delete the 5.1%**: I designed the DQ layer to
*detect and quantify* rather than *quietly remove*. A reviewer can see exactly
which rows are suspect and judge for themselves. Auto-removing risks silently
deleting legitimate re-postings — and 5.1% is low enough not to materially
distort the dashboard numbers.

The bigger lesson: **a multi-column exact match is often a smarter dedup
strategy than a similarity score.** Saying "I used `fuzzywuzzy` with a 90%
threshold" sounds sophisticated, but it forces you to defend an arbitrary
number. Saying "I matched on title + company + state + suburb within a 7-day
window because that combination characterises a re-posting" is something you
can defend in an interview.

---

## Lesson 2: Schema design decisions that look obvious are usually wrong

Four design calls where the "obvious" answer would have hurt the model:

### 2a. Fact PK is a surrogate, not the Adzuna `job_id`

Adzuna's `job_id` is a perfectly good natural key. I still introduced a
surrogate `job_posting_id BIGINT AUTO_INCREMENT` as the fact PK. Standard
Kimball practice — stable integer joins are faster, the surrogate isolates the
mart from any upstream re-numbering, and `job_id` is preserved in the fact as
a degenerate dimension (so I can still trace back to source).

### 2b. Skills go in a bridge table, not as columns

The naive design is `skill_1`, `skill_2`, `skill_3` columns on the fact. Two
problems:

1. How many columns is enough? Any fixed number is wrong.
2. The alternative — one row per (job, skill) pair in the fact — would inflate
   the fact's grain (one job posting → multiple rows) and break every
   aggregation that counts jobs.

A bridge table (`bridge_job_skills`, PK = `(job_posting_id, skill_id)`) is the
Kimball-standard solution for many-to-many between a fact and a dimension. The
fact's grain stays at "one job posting per row," and skill analyses work by
joining through the bridge.

### 2c. Salary stays as the API gave it (no regex extraction from description)

The API populates `salary_min` / `salary_max` for only 9.8% of rows. The
tempting workaround is to regex-extract salaries from the `description` field
(`$130K-150K` and so on). I evaluated this and rejected it without writing
production code, on three grounds:

1. **Yield is low**: only 195 rows contain a `$` in the description, and many
   are noise (`$781M in funding`, `$11B valuation` — company financials, not
   salaries).
2. **Unit disambiguation is hard in pure SQL**: `Daily rate $850-$900`,
   `$130K annual`, `$60/hr` — three different units. Python regex with
   capture groups could handle this; T-SQL `PATINDEX` cannot, cleanly.
3. **Expected value is negative**: maybe lift coverage from 9.8% to ~18%, but
   in exchange introduce confidence-destroying noise where some "salaries" are
   actually valuations.

So salary coverage stays at 9.2% (after also discarding 13 sub-$30K outliers —
see Lesson 4 below). That number is reported honestly on every dashboard and
in the README. **A defensible 9.2% beats an indefensible 18%.**

### 2d. Location is denormalised into five columns, not snowflaked

`dim_location` has `country`, `state`, `region`, `city`, `suburb` as separate
columns rather than a single concatenated address string or a snowflaked
`dim_country → dim_state → dim_city` chain. Two reasons:

- **Power BI drill-down works on hierarchies**: a user clicking "Australia"
  should be able to drill into "NSW → Sydney → Surry Hills." Flattening to one
  string makes that impossible.
- **Star beats snowflake for downstream BI**: snowflaking is theoretically
  cleaner but creates extra joins on every query. With Power BI as the
  consumer, star-schema query plans are noticeably better.

The Adzuna source provides `location.area` as a hierarchical JSON array
ranging from 1 to 6 levels deep, so the columnar layout maps naturally.

---

## Lesson 3: Data quality is plumbing, not paperwork

I wrote a dedicated `03_dq_staging.sql` containing read-only SELECT checks
that run between staging and mart. Categories:

| Check | What it asserts |
|---|---|
| Row counts | `staging = 2,142`, fact = 2,142 (grain preserved) |
| PK uniqueness | `COUNT(*) = COUNT(DISTINCT job_id)` |
| Referential integrity | Zero `missing_company`/`missing_location`/`missing_date`/`missing_category` after the joins to dims |
| NULL completeness | Quantify NULL rates on critical columns (title, company, posted_date all 0; state 228) |
| Value ranges | Salary sanity (no inverted ranges, no above-$1M, flag below-$30K); date ranges (no future dates, no parse failures) |
| Coverage metrics | Location-hierarchy completeness, skill coverage, salary coverage all quantified |
| Fuzzy duplicates | Check 5 and Check 5b run side by side |

Honest disclosure: this is **not** a real test framework. There is no Great
Expectations, no `dbt test`, no `pytest`. It is read-only SELECTs run manually
in MySQL Workbench, with the result grid as the pass/fail signal.

For a portfolio at this scale that is the right level of rigour — a real test
framework would be 3-4x the project complexity for negligible benefit. But I
am explicit about it in the docs so a reviewer knows what they are looking at.
The lesson: **DQ checks earn their keep by being run, not by the framework
they sit in.** A well-named SELECT in a versioned file is a perfectly good
contract.

---

## Lesson 4: Always look at the floor of the distribution

A late catch during salary processing: I ran a `MIN(salary_avg)` and saw `98`.
Thirteen rows had `salary_avg < $20,000`.

The cause (most likely): the Adzuna API field is supposed to be annual salary,
but a few postings put an **hourly rate** in there — so a $98 number is
actually $98/hour, perfectly reasonable, just in the wrong field.

I added Step 4 to the staging pipeline: any `salary_min` below 30,000 AUD gets
cleared to `NULL`. The threshold is the Australian full-time legal minimum
(~$47,000 annual) minus a safety margin. After Step 4:

- `min(salary_avg)` rose from 98 → 45,000
- Salary coverage fell from 9.8% to 9.2% (the 13 rows now contribute NULL to
  the mean)

The principle: **always look at both extremes of a numeric distribution before
trusting the mean.** A clean-looking mean can hide outliers that destroy
downstream credibility — and a Junior DA who can defend "why are there 13 rows
under $20K?" in an interview is doing much better than one who shipped a
broken mean.

---

## Lesson 5: A constraint inherited from Week 1 — Adzuna's 500-character truncation

This belongs in Week 2's lesson because it directly shaped how I designed the
skills layer of the schema. The skill-extraction story is also the place I
first discovered the constraint.

### How I found it

I ran the skill-match join and looked at the top skills. The result was
visibly broken: **Machine Learning** at 113 mentions led the chart, **SQL** had
22, **Python** 18. SQL appearing in only 1% of data-job descriptions is not a
plausible market reality.

I assumed first that my MySQL `\b` word-boundary was failing. I ran an
A/B test: `REGEXP '\\bSQL\\b'` vs `REGEXP 'SQL'` vs `LIKE '%SQL%'`. All three
returned 22. The regex was fine — the data wasn't.

Then I looked at the descriptions themselves:

```sql
SELECT AVG(LENGTH(description)), MAX(LENGTH(description)),
       SUM(CASE WHEN description LIKE '%…' THEN 1 ELSE 0 END) AS truncated
FROM raw_jobs;
-- → avg 500, max 500, truncated 2,141 / 2,142
```

99.95% of descriptions are exactly 500 characters and end in `…`. Adzuna's
free tier truncates description at 500 chars, and skill requirements
typically appear in the *Requirements* or *Technical Skills* section,
i.e. later in the body. The section that lists Python and SQL is being cut
off before extraction even starts.

### What it means for the portfolio

- **Skill coverage is capped at ~14%** (293 of 2,142 jobs match at least one
  skill). This is a structural ceiling, not a tuning parameter.
- Skill counts on the dashboard are **indicative**, not exhaustive. The
  dashboard labels them as such, and the README explains the cause.
- Auto-extracting from a redirect URL would require scraping, which is
  out-of-scope for this portfolio (and possibly TOS-violating). I chose
  "honest reporting" over "more numbers."

### The same upstream issue affects salary differently

The 9.2% salary coverage is **not** a truncation problem — it is a separate
constraint of the Australian Adzuna market. The API's `salary_min`/`max`
fields are `NULL` 90.2% of the time because Australian job listings
conventionally do not disclose salary publicly.

Two distinct upstream limits, one consistent design response: **report what
the source gives you, quantify the gap honestly, do not invent data to plug
holes.**

---

## What I would do differently

1. **Build the DQ harness before the transforms, not after**. I wrote the
   transforms, then the DQ checks. The right order is to write the assertions
   first (or at least sketch them), then write the transform to satisfy them.
2. **Version-control the DQ output snapshots**. The DQ SQL is in the repo,
   but the *result of each run* is not. A reviewer who wants to verify my
   coverage claims has to re-run the queries. I should have committed a
   markdown snapshot of each DQ result block alongside the SQL.
