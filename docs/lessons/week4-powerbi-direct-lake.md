# Week 4 — Power BI Direct Lake Dashboard

## TL;DR

Built a two-page Power BI dashboard on top of a Direct Lake semantic model
connected to the Fabric Warehouse. The dashboard answers four business
questions (who is hiring, what they pay, what skills they want, how demand
trends over time) and is honest about the data's limits at every step.

Three lessons stood out — one is a Direct Lake debugging story that taught me
how invisible model-level state can be, one is about a dataset assumption I
made and almost shipped with, and one is about a Direct Lake limitation that
shapes how this kind of model can be shared.

---

## Lesson 1: In Power BI, an inactive relationship is invisible but decisive

This was the debugging story of the week. Symptom: every KPI card that
referenced a date filter returned `--` (blank) instead of a number. The
filter `full_date >= 2026/3/1` produced BLANK; the inverse `<= 2026/3/1`
produced 2,142 (the entire row count). Neither is a sensible result.

### The diagnostic path

I ran an A/B test in the Service-side DAX query view, because I needed to
isolate whether the bug was in the filter, the measure, or the model:

```dax
EVALUATE
ROW (
    "no_filter",   CALCULATE ( COUNTROWS ( fact_job_postings ) ),
    "lte_3_1",     CALCULATE ( COUNTROWS ( fact_job_postings ),
                               dim_date[full_date] <= DATE ( 2026, 3, 1 ) ),
    "gte_3_1",     CALCULATE ( COUNTROWS ( fact_job_postings ),
                               dim_date[full_date] >= DATE ( 2026, 3, 1 ) )
)
-- Result: 2142, 2142, BLANK
```

`lte_3_1 = 2142` is the smoking gun. Even with no filter on a 78-day date
range, that number can only appear if **the filter is being ignored**. A real
filter would have returned ~32 (the rows before 2026-03-01).

I ran further DAX checks against `dim_date[full_date] <= DATE(2020, 1, 1)`
(BLANK, correct — no jobs predate 2025), and against `dim_date[year] = 2026`
(2,133, correct). So filters on *other* `dim_date` columns worked; only
`full_date` was broken.

### What it actually was

Earlier in the build I had experimented with manually adding a relationship
between `fact[date_id]` and `dim_date[full_date]` (a type mismatch — INT
against DATE — and a bad idea I quickly reverted). What I missed is that
Power BI enforces a rule that two tables can have only one **active**
relationship at a time. When I added the bad one, Power BI silently demoted
the original `fact[date_id] ↔ dim_date[date_id]` relationship to *inactive*.

Deleting the bad relationship didn't restore the original — it stayed
inactive. The fact-to-dim path was technically still there in the model
diagram, but it wasn't propagating filters. So `dim_date[full_date]` filter
context could not push down to `fact_job_postings`, and the engine returned
BLANK rather than fail loudly.

Fix: open the relationship dialog, tick **Is active**, save. Re-run the DAX —
all numbers correct.

### The lesson

Two things came out of this:

1. **A relationship's existence in the diagram is not the same as it being
   live.** The active/inactive flag is a property hidden one click deep in the
   edit dialog. It is the single most consequential boolean in a Power BI
   model.
2. **Sanity-check filter behaviour with deliberately asymmetric tests.**
   `lte_3_1 = 2142` was meaningless on its own, but absurd when juxtaposed
   against the expected (~32). DAX query view exists for exactly this kind of
   isolation testing — don't try to diagnose by squinting at visuals.

---

## Lesson 2: Reading "61 active days" as "the last 61 days" is the kind of mistake that ships

When I first looked at the date-range Card, it said `2025-07-29 to 2026-05-15
(78 days)`. I almost moved on. A span of nearly a year and 78 distinct dates
felt fine.

It is not fine. 78 distinct dates over a 290-day span means the data is
**sparse**, not continuous — and a daily trend chart on sparse data is
visually noisy in a way that destroys the narrative.

I ran a `GROUP BY year_month` and the truth came out:

| Period | Distinct days | Jobs |
|---|---|---|
| 2025-07 to 2026-02 | ~10 days | 32 jobs (sparse, scattered) |
| 2026-03 | 18 days | 62 jobs (testing ingestion) |
| 2026-04 | 28 days | 456 jobs (ramping up) |
| 2026-05 | 15 days | 1,592 jobs (full daily ingestion) |

Those scattered 2025 dates are the ingestion artefact of building the
pipeline. They are not the market. They are me, learning to run the
extraction script.

### The fix and the disclosure

I applied a page-level filter (`full_date >= 2026/3/1`), narrowing the
"analysis window" to 61 active days across March–May 2026. The Card became:

> Analysis window: 2026-03-02 to 2026-05-15 (61 active days)

And the trend chart shipped with an explicit caveat about pipeline maturity:

> Pipeline maturity timeline:
> - March 2026: sparse testing ingestion (18 active days, 62 jobs)
> - April 2026: ramp-up to daily ingestion (28 days, 456 jobs)
> - May 2026: full daily production (15 days, 1,592 jobs)
>
> The visible non-continuity in March reflects our ETL pipeline maturing —
> not a market downturn.

### The lesson

A summary statistic like "78 distinct dates over X to Y" hides the
**distribution**. The fact that 95% of the rows live in the last six weeks of
a ten-month window is something I could only see by grouping monthly and
counting. The rule I took away: **whenever a dataset spans more than a few
weeks, group the row count by month before doing anything else.** A flat
"date range" summary will lie to you.

---

## Lesson 3: Direct Lake is for the enterprise, not for public-link portfolios

I picked Direct Lake mode in Week 4 over Import or DirectQuery, on the
reasonable grounds that:

- The data already lives in OneLake as Parquet — Direct Lake reads it
  zero-copy
- It demonstrates the Fabric-native architecture that motivated migrating the
  warehouse in the first place
- At 2,142 rows the performance differences are negligible, but the
  *capability story* is stronger

Then I tried to publish the report to the public web (so a recruiter could
view the dashboard without a Microsoft account). The Service returned:

> Your report is not eligible for publishing to the web.

After checking the documentation, the constraint is at the architecture
level: **reports with a live connection to a Direct Lake semantic model are
not eligible for Publish-to-Web.** Direct Lake's promise — read data live
from OneLake — is fundamentally a within-tenant feature. Anonymous public
embed implies hosting the data outside the tenant's auth boundary, which
Direct Lake won't do.

### The decision I had to make

The options were:
- Convert to **Import mode** (preserves Publish-to-Web, loses the Direct Lake
  story)
- Stick with Direct Lake and **share via screenshots / live-demo in
  interviews** (preserves the technical story, hurts asynchronous reach)

I picked the second. The Direct Lake architecture is more interesting to a
reviewer than convenience-of-access, and the screenshots in the README convey
the dashboard's content well enough for first-pass evaluation. The live
walkthrough during an interview is, separately, a better experience anyway
— I can narrate decisions in real time.

### The lesson

**Choose a technical architecture for the audience you actually have.** Direct
Lake is the right choice for an enterprise Fabric tenant where everyone has
SSO into the same workspace. It is not the right choice for a public
portfolio whose primary access pattern is "recruiter clicks a link." If I
were optimising purely for portfolio reach, Import mode would have been
correct. I'm comfortable with this trade-off because the Direct Lake decision
itself is part of what I want recruiters to evaluate — but it took a hard
constraint at the publish step to make that trade-off explicit.

---

## What I would do differently

1. **Spike the publish/share path on day one.** I designed the storage mode
   for technical correctness without checking whether the resulting model
   could be shared the way I needed. A 10-minute test ("can I publish-to-web
   a Direct Lake report?") at the start of Week 4 would have surfaced this
   constraint before I committed to the architecture.
2. **For any future Direct Lake project where filter behaviour misbehaves, go
   straight to the relationship's *active* flag.** That's the first thing to
   check, not the last.
