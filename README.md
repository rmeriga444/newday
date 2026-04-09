# NewDay dbt Project

This project transforms raw sales data into business-ready analytics using a medallion
architecture on Snowflake. It was built with dbt Core and covers revenue analysis,
customer segmentation, payment method performance, operational flags, and seasonal patterns.


## What this project does

The pipeline reads from seven raw CSV tables loaded into Snowflake and produces seven
Gold analytics models answering specific business questions. Everything runs in three
layers — Bronze, Silver, and Gold — each with a clear and distinct responsibility.

Raw data flows through Bronze views that preserve source fidelity, into Silver incremental
tables that clean, type-cast, and enrich the data, and finally into Gold tables that
aggregate and shape it for business consumption.


## Project structure

```
newday/
├── dbt_project.yml
├── packages.yml
├── profiles.yml
├── submission.txt
│
├── macros/
│   ├── generate_surrogate_key.sql
│   ├── generate_schema_name.sql
│   ├── safe_divide.sql
│   ├── date_range_filter.sql
│   └── get_incremental_timestamp.sql
│
├── models/
│   ├── bronze/
│   │   ├── sources.yml
│   │   ├── schema.yml
│   │   ├── sales_fact.sql
│   │   ├── customers.sql
│   │   ├── products.sql
│   │   └── product_category.sql
│   │
│   ├── silver/
│   │   ├── schema.yml
│   │   ├── sales_fact.sql
│   │   ├── customers.sql
│   │   ├── products.sql
│   │   ├── product_category.sql
│   │   └── sales_enriched.sql
│   │
│   └── gold/
│       ├── schema.yml
│       ├── revenue_by_category_monthly.sql
│       ├── revenue_edge_cases.sql
│       ├── customer_segments.sql
│       ├── payment_analysis.sql
│       ├── flagged_orders.sql
│       ├── seasonal_patterns.sql
│       └── daily_revenue.sql
│
└── tests/
    └── generic/
        └── (17 custom test files)
```


## Architecture

### Bronze

Bronze models are views. They sit directly on top of the RAW schema tables and
pass all source columns through unchanged. A single `load_ts` timestamp column is
added to record when the row was queried. No casting, no filtering, no business
logic. The point is to have a stable, always-current mirror of the source that
Silver can depend on without being coupled to the RAW schema directly.

### Silver

Silver models are incremental tables using a merge strategy on surrogate keys. This
is where all the actual transformation work happens. Every column is explicitly cast
using `TRY_CAST` so bad source values surface as NULL rather than crashing the run.
Nullable fields like `discount_applied` and `shipping_cost` are coalesced to zero
with the original nullability preserved in `_was_null` boolean columns.

Each row gets a `_processed_at` timestamp and an MD5 surrogate key derived from its
natural key. On incremental runs only rows newer than the latest `_processed_at` in
the target table are processed, which keeps run times fast as the dataset grows.

The `sales_enriched` model is a Silver view that joins all four Silver tables together
into one denormalised record set. All Gold models read from this single source rather
than writing their own joins, which keeps the Gold layer clean and focused on
aggregation logic.

### Gold

Gold models are clustered tables. Each one answers one of the seven analytical
questions in the assignment. They all read from `sales_enriched` and produce a
`_refreshed_at` audit timestamp on every run. Grain and key output columns are
documented in `submission.txt`.


## Snowflake setup

Before running dbt, the Snowflake environment needs to be prepared. Run the following
as `ACCOUNTADMIN` in a Snowflake worksheet.

```sql
use role accountadmin;

create database if not exists newday_dev;
create database if not exists newday;

create schema if not exists newday_dev.raw;
create schema if not exists newday_dev.bronze;
create schema if not exists newday_dev.silver;
create schema if not exists newday_dev.gold;

create schema if not exists newday.raw;
create schema if not exists newday.bronze;
create schema if not exists newday.silver;
create schema if not exists newday.gold;

create role if not exists developer;
create role if not exists analyst;
create role if not exists reporting;

grant usage on warehouse compute_wh to role developer;
grant usage on database newday_dev   to role developer;
grant usage, create table, create view on schema newday_dev.raw    to role developer;
grant usage, create table, create view on schema newday_dev.bronze to role developer;
grant usage, create table, create view on schema newday_dev.silver to role developer;
grant usage, create table, create view on schema newday_dev.gold   to role developer;

grant select on future tables in schema newday_dev.gold to role analyst;
grant select on future tables in schema newday_dev.gold to role reporting;

grant role developer  to user ROHITMERIGA;
grant role analyst    to user ROHITMERIGA;
grant role reporting  to user ROHITMERIGA;
```

Then load the seven CSV files into `newday_dev.raw` using Snowflake's internal stage:

```sql
create or replace file format newday_dev.raw.csv_format
    type = csv field_delimiter = ',' skip_header = 1
    field_optionally_enclosed_by = '"' empty_field_as_null = true trim_space = true;

create or replace stage newday_dev.raw.raw_stage
    file_format = newday_dev.raw.csv_format;
```

Upload files via SnowSQL:
```bash
snowsql -c newday
PUT file://sales_fact.csv        @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
PUT file://customer.csv          @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
PUT file://product.csv           @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
PUT file://product_category.csv  @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
PUT file://kafka_stream.csv      @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
PUT file://subscription_data.csv @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
PUT file://weather_data.csv      @newday_dev.raw.raw_stage AUTO_COMPRESS=FALSE;
```

Then run `COPY INTO` for each table from the Snowflake worksheet.


## Local setup

```bash
# Create a virtual environment to keep dbt isolated
python3 -m venv ~/.dbt-env
source ~/.dbt-env/bin/activate

# Install dbt with the Snowflake adapter
pip install dbt-snowflake

# Set up your connection profile
mkdir -p ~/.dbt
cp profiles.yml ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml and add your Snowflake password

# Install dbt packages
dbt deps

# Verify the connection is working
dbt debug
```


## Running the project

```bash
# Full pipeline — Bronze, Silver, Gold, and all tests
dbt build

# First run or after schema changes on Silver
dbt build --full-refresh

# Run a single layer
dbt run --select tag:bronze
dbt run --select tag:silver
dbt run --select tag:gold

# Run a specific model and everything it depends on
dbt run --select +customer_segments

# Run Q7 with a custom date window
dbt run --select daily_revenue \
        --vars '{"start_date": "2024-06-01", "end_date": "2024-06-30"}'

# Run all tests
dbt test

# Generate and browse documentation locally
dbt docs generate
dbt docs serve
```


## Project variables

All thresholds and configuration values are kept in `dbt_project.yml` rather than
hardcoded in SQL. They can be overridden at run time using `--vars`.

| Variable | Default | Used in |
|---|---|---|
| `start_date` | `2024-01-01` | daily_revenue |
| `end_date` | `2024-12-31` | daily_revenue |
| `tier_high_value` | `1000` | customer_segments |
| `tier_medium_value` | `500` | customer_segments |
| `flag_discount_threshold` | `0.30` | flagged_orders |
| `flag_shipping_pct` | `0.10` | flagged_orders |
| `sk_delimiter` | `\|\|` | generate_surrogate_key |


## Testing

The project has three layers of test coverage.

Built-in dbt tests (`unique`, `not_null`, `accepted_values`, `relationships`) are
declared in each layer's `schema.yml` and cover primary keys, foreign keys, and
allowed value sets.

The `dbt_expectations` package adds regex validation on email columns and numeric
range checks on financial fields.

Seventeen custom generic tests in `tests/generic/` cover production-specific failure
modes that the built-in tests cannot catch: duplicate surrogate keys, orphaned foreign
keys, fan-out from non-unique joins, silent null regressions, data loss between
Bronze and Silver, composite grain uniqueness on Gold models, and model freshness.


## dbt Cloud deployment

Once the project is connected to a Git repository, set up two environments in
dbt Cloud — Development and Production — pointing at `newday_dev` and `newday`
respectively. The `generate_schema_name` macro ensures schemas are always named
`BRONZE`, `SILVER`, and `GOLD` regardless of which environment is running.

A production job with the commands `dbt deps` and `dbt build` on a daily schedule
covers the full pipeline including tests.
