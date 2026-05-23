# Week 1 — Extraction and Toolchain Decisions

## TL;DR

Built a Python ingestion script that pulls Australian data-job postings from the
Adzuna public API into a flat staging table in MySQL. Two upstream decisions
shaped everything downstream: **Python for extract, SQL for transform** (play to
my strongest skill), and **flat staging without nested JSON expansion** (defer
shape decisions until I understand the data better).

---

## Lesson 1: Pick your toolchain by where you are strongest, not by what is most fashionable

I evaluated three setups before writing a line of code:

- All-Python (pandas / SQLAlchemy / DuckDB)
- All-SQL (use a server-side HTTP function or external ingest tool)
- **Python for Extract, SQL for Transform** (what I picked)

I picked the split because SQL is my strongest analytical surface and I wanted
the Transform layer — where star-schema decisions, deduplication logic, and
data-quality checks live — to be in code that I can read fluently and that a
future reviewer can audit without leaving the database. Python only does what
Python is genuinely better at: HTTP, pagination, JSON parsing, retry logic.

The takeaway is not "Python is bad for transforms" — it is "use your strongest
tool for the part of the pipeline that earns the most scrutiny." For a junior DA
portfolio, the transform layer is exactly where reviewers look.

---

## Lesson 2: Flat staging is a deliberate choice, not laziness

Adzuna returns nested JSON: `location.area` is an array, `category` is a sub-
object, `salary_min` / `salary_max` may be `null`. The "obvious" thing to do is
normalise immediately — expand `location.area` into `country / state / city`,
split `category`, validate salaries against a known range.

I did the opposite. The staging table is intentionally flat with the raw JSON
payload preserved in a single column:

- I do not yet know which fields are reliable, so any normalisation done now is
  guessing
- If a downstream decision changes (e.g. "we now also need region"), I do not
  want to re-pull from the API
- The Adzuna API is rate-limited (free tier) — re-extraction is genuinely costly

Flat staging let me ship the extract in one afternoon and defer every shape
question to Week 2, when I had enough sample data to make those decisions on
evidence rather than guesswork. The cost is one extra transform step. The
benefit is that I can change my mind cheaply.

---

## Lesson 3: A constraint discovered in Week 1 propagates everywhere

While inspecting raw payloads I noticed every `description` field was exactly
500 characters and ended in "…". Adzuna's free tier truncates descriptions.

I documented this immediately and did not try to work around it (no scraping
of the `redirect_url`, no LLM-based skill extraction from partial text). The
reason is simple — I would rather ship a portfolio with a 13.7% skill-coverage
caveat that I can defend, than ship one with imputed values I cannot.

The full impact analysis (skill detection ceiling, alternative attempts I
considered and rejected) lives in `week2-transform-and-dq.md` because it
manifests as a transform-layer constraint. The Week 1 lesson is just this:
**when you find a hard limit at the source, write it down on day one and let
every subsequent week design around it.**

---

## What I would do differently

Nothing in Week 1 — but I would push back on a younger version of myself who
might have been tempted to "fix" the truncation problem with scraping. Time
spent fighting an upstream limit is time not spent on transform, modelling,
and dashboards, which is where a Junior DA portfolio is actually evaluated.
