# Insights — Australian Data Job Market

This document captures the analytical findings from the Power BI dashboard
built in Week 4. The data spans **2026-03-02 to 2026-05-15** — 61 active days
of postings extracted from the Adzuna AU API.

The findings are presented honestly: where the data supports a strong claim, I
state it directly; where the source's known limitations cap what I can
conclude, I flag that openly.

---

## Scope and known constraints

Before the findings, two constraints frame what this analysis can and cannot
say:

### Constraint 1 — Adzuna does not return closed postings

The Adzuna API only exposes jobs that are still open at the time of the call.
Jobs that have been filled and closed never appear, regardless of when they
were posted. This means our "trend" view is really a **snapshot of what was
_still active_ on the day we extracted**, not a true measure of how many jobs
were posted on each calendar day.

**Implication**: The strong upward slope in the daily trend chart is partly a
real effect of pipeline maturity (we moved from sparse to daily ingestion) and
partly an artefact of how Adzuna's data ages — older days have fewer jobs
still open because more of them have since been filled. Cleanly separating the
two would require historical re-extraction, which Adzuna's free tier doesn't
allow.

### Constraint 2 — Adzuna's free tier truncates descriptions at 500 characters

Job descriptions on the free API are cut off at 500 characters. The technical
skills section of a job description usually sits in the middle or end of the
posting (under "Requirements" or "Technical Skills"), so it gets cut off
before our skill matcher ever sees it.

**Implication**: Skill counts are **indicative, not exhaustive**. Only ~14% of
the 2,110 jobs in scope contributed any matched skill. Salary coverage is
even thinner at 9.2%, but for a different reason — Australian job listings
conventionally do not disclose salary publicly, and Adzuna passes that gap
through. Both numbers are reported on the dashboard so readers can calibrate.

---

## Finding 1 — Hiring is concentrated on the east coast

Among the cities resolved at city granularity, **Sydney, Melbourne, and
Brisbane lead by a wide margin**:

| City      | Job postings (Mar 2 – May 15) |
| --------- | ----------------------------- |
| Sydney    | 500                           |
| Melbourne | 191                           |
| Brisbane  | 130                           |
| Adelaide  | 41                            |
| Perth     | 38                            |

A further 373 postings (17.7% of the dataset) lack a city-level location and
appear as "Unknown" — the Adzuna source returns only `country = Australia`
for these without further granularity. They are not excluded, so the reader
can see the magnitude of the coverage gap directly.

**Takeaway**: The Australian data-job market is heavily east-coast skewed.
Adelaide (where I am based) ranks 6th — a smaller market, but not absent.

---

## Finding 2 — Mean salary exceeds median, suggesting a senior-heavy market

For the 9.2% of postings (197 jobs) that disclose salary:

- **Average salary**: $154,810 AUD
- **Median salary**: $140,000 AUD

The mean sits ~10% above the median. In a roughly symmetric distribution
these would be close; a sustained gap of this size implies the distribution
is right-skewed by a cluster of high-end roles. Reading the salary
distribution histogram confirms this: there are visible clusters at $160K–
$200K and $200K+, alongside the dominant $130K–$160K mid-band.

**Takeaway**: Senior data professionals appear to command meaningful premiums
in the Australian market — high-end salaries are common enough to lift the
mean noticeably above the median, even on a small (n=197) sample.

---

## Finding 3 — Demand exists across seniority, but the analysis window matters

Across the full 61-day window (March 2 – May 15, 2026):

- **2,110 job postings**
- **805 distinct companies**
- Salary distribution skewed toward the $100K–$160K bands (the bulk of mid-
  band entries)

Tightening the window to **May 1 – May 15** (the period with the densest
daily ingestion):

- **1,500+ job postings** (~71% of the 61-day total, in 14% of the days)
- **649 distinct companies**

**Takeaway**: The mid-May window concentrates a disproportionate share of the
postings — partly real market activity, partly the pipeline-maturity effect
explained in Constraint 1. The presence of 649 distinct companies posting in
just two weeks does suggest genuine breadth of demand. Combined with the
salary distribution sitting predominantly below $160K, the data is consistent
with **a market that has substantial junior-to-mid-level openings**, not just
a senior-heavy concentration.

---

## Finding 4 — Cloud platforms lead the May skills demand

Looking at **May 2026 alone** (the most reliably-ingested two weeks of the
window), the top-mentioned skills shift compared to the full-period ranking:

- **Cloud platforms lead**: AWS and Azure dominate the top of the list
- **SQL, Power BI, and Python** form the second tier
- **Databricks, Machine Learning, and Snowflake** — typically asked of senior
  data engineers and ML practitioners — also rank prominently

**Takeaway**: For the May snapshot, cloud platform proficiency appears more
heavily emphasised in postings than foundational programming languages. One
plausible reading is that Python and SQL are increasingly treated as
_assumed_ baseline skills (and thus less often called out explicitly), while
cloud platform names are listed precisely because they differentiate roles.
This matches my own anecdotal experience reading Australian data job ads.

---

## Finding 5 — Three skill categories dominate

Rolling the top-mentioned skills into broader categories:

| Category       | Examples                              |
| -------------- | ------------------------------------- |
| **Cloud**      | AWS, Azure, GCP                       |
| **Database**   | SQL, Snowflake, Databricks, Lakehouse |
| **BI tooling** | Power BI, Tableau                     |

These three categories cover the majority of skill mentions. Programming
languages (Python, Scala) and modelling toolkits (ML, scikit-learn-class
items) appear but with thinner counts.

**Takeaway**: For a Junior DA target profile, **demonstrable competence across
all three categories — at least one cloud, SQL, and one BI tool — covers most
of the explicit skill demand visible in the market**.

---

## Finding 6 — IT-classified roles drive the bulk of postings

Adzuna's category taxonomy assigns each posting to a job family. In this
dataset, IT-related categories account for **roughly 60%+** of all postings,
with engineering and finance/accounting making up the next-largest blocks.

**Takeaway**: "Data" hiring is overwhelmingly classified under IT in
Australia, even when the day-to-day role sits closer to business analysis.
This affects how candidates should search — filtering on "IT Jobs" returns
the majority of relevant data roles, while pure "Data" or "Analytics"
filters will miss substantial volume.

---

## What this analysis _cannot_ say

For clarity, here is what the data and methodology **do not support**:

- **Role-level salary comparison (DA vs DE vs DS)** — Adzuna's category
  taxonomy is too coarse to separate these reliably, and parsing role from
  title-string is not reliable enough to ship. The dashboard does not break
  salary out by role family for this reason.
- **A real time series of _posting_ activity** — see Constraint 1. The
  dashboard's daily trend is honestly labelled as showing only currently-
  active jobs.
- **Skill demand below the long tail** — anything mentioned in fewer than ~5
  postings is statistical noise at this sample size and is not interpreted.

---

## Reproducibility

Every finding above was derived from the Fabric Warehouse star schema
(`adzuna_warehouse`), and is reproducible from the SQL in `sql/fabric/` and
the Power BI semantic model `adzuna_semantic_model` in the
`adzuna-job-market-pipeline` workspace. Dashboard screenshots in
`docs/screenshots/` show the visuals these findings came from.
