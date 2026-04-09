# NewDay dbt Project

This project transforms raw sales data into business-ready analytics using a medallion
architecture on Snowflake. It covers revenue analysis, customer segmentation, payment
method performance, operational flags, and seasonal patterns across seven analytical models.


## Architecture

The pipeline runs across three layers — Bronze, Silver, and Gold — each with a clear
and distinct responsibility.

```
RAW (Snowflake)
    └── BRONZE  (views)
            └── SILVER  (incremental tables)
                    └── GOLD  (analytical tables)
```

### Bronze

Views that sit directly on top of the RAW schema tables. Every source column is passed
through unchanged. A single `load_ts` column is added using `convert_timezone('UTC',
current_timestamp())` to record when the row was queried. No casting, no business logic.

### Silver

Incremental tables using merge strategy on surrogate keys. All transformation happens
here — explicit `TRY_CAST` on every column, null-safe coalescing, MD5 surrogate key
generation, temporal decomposition, and business flags. The `load_ts` column marks when
Silver processed each row. The `sales_enriched` view joins all four Silver tables into
one denormalised record set that all Gold models read from.

### Gold

Clustered tables answering the seven analytical questions. Each model reads from
`sales_enriched` and produces a `load_ts` column on every run.


## Project structure

```
newday/
├── dbt_project.yml
├── packages.yml
├── profiles.yml
├── requirements.txt
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
│   │   ├── raw_sales_fact.sql
│   │   ├── raw_customers.sql
│   │   ├── raw_products.sql
│   │   └── raw_product_category.sql
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
│       ├── revenue_by_category_monthly.sql    Q1
│       ├── revenue_edge_cases.sql             Q2
│       ├── customer_segments.sql              Q3
│       ├── payment_analysis.sql               Q4
│       ├── flagged_orders.sql                 Q5
│       ├── seasonal_patterns.sql              Q6
│       └── daily_revenue.sql                  Q7
│
└── tests/
    └── generic/
        └── 17 custom test files
```


## Snowflake setup

Run the following as `ACCOUNTADMIN` once before the first dbt run.

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

grant usage on warehouse compute_wh      to role developer;
grant usage on database  newday_dev      to role developer;
grant usage, create table, create view on schema newday_dev.raw    to role developer;
grant usage, create table, create view on schema newday_dev.bronze to role developer;
grant usage, create table, create view on schema newday_dev.silver to role developer;
grant usage, create table, create view on schema newday_dev.gold   to role developer;

grant usage on database  newday          to role developer;
grant usage, create table, create view on schema newday.raw    to role developer;
grant usage, create table, create view on schema newday.bronze to role developer;
grant usage, create table, create view on schema newday.silver to role developer;
grant usage, create table, create view on schema newday.gold   to role developer;

grant select on future tables in schema newday_dev.gold to role analyst;
grant select on future tables in schema newday_dev.gold to role reporting;
grant select on future tables in schema newday.gold     to role analyst;
grant select on future tables in schema newday.gold     to role reporting;

grant role developer  to user ROHITMERIGA;
grant role analyst    to user ROHITMERIGA;
grant role reporting  to user ROHITMERIGA;
```

Load the seven CSV files into `newday_dev.raw` using an internal Snowflake stage:

```sql
create or replace file format newday_dev.raw.csv_format
    type = csv field_delimiter = ',' skip_header = 1
    field_optionally_enclosed_by = '"' empty_field_as_null = true trim_space = true;

create or replace stage newday_dev.raw.raw_stage
    file_format = newday_dev.raw.csv_format;
```

Upload via SnowSQL from the directory containing the CSV files:

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
python3 -m venv ~/.dbt-env
source ~/.dbt-env/bin/activate
pip install -r requirements.txt

mkdir -p ~/.dbt
cp profiles.yml ~/.dbt/profiles.yml
```

Edit `~/.dbt/profiles.yml` and add your Snowflake password to both dev and prod outputs.

```bash
dbt deps
dbt debug
```


## dbt Cloud setup

### Environments

Create two environments under **Deploy → Environments**:

| Environment | Type | Database | dbt version |
|---|---|---|---|
| Development | Development | NEWDAY_DEV | 1.8 (latest) |
| Production | Deployment | NEWDAY | 1.8 (latest) |

### Production job

Create a job under **Deploy → Jobs** with these commands:

```
dbt deps
dbt build
```

Schedule: daily at 06:00 UTC, Monday to Friday.


## Deployment workflow

Code moves from Dev to Prod through git:

```
Dev IDE  →  commit + push  →  merge to main  →  Production job runs
```

1. Write and test code in the Dev IDE against `NEWDAY_DEV`
2. Commit and push from the IDE git panel
3. Merge the branch to `main`
4. The Production job picks up the latest `main` and runs against `NEWDAY`


## Running the project

```bash
dbt build                                        # full pipeline + all tests
dbt build --full-refresh                         # rebuild Silver from scratch
dbt run --select tag:bronze                      # bronze only
dbt run --select tag:silver                      # silver only
dbt run --select tag:gold                        # gold only
dbt run --select +customer_segments              # model and all upstream
dbt run --select tag:silver --full-refresh       # force rebuild Silver

dbt run --select daily_revenue \
  --vars '{"start_date":"2024-06-01","end_date":"2024-06-30"}'

dbt test
dbt source freshness
dbt docs generate
dbt docs serve
```


## Gold models

| Model | Answers |
|---|---|
| `revenue_by_category_monthly` | Total revenue by product category per month |
| `revenue_edge_cases` | Zero-quantity handling and payment method % split per month and category |
| `customer_segments` | High / Medium / Low value tiers with customer names and order counts |
| `payment_analysis` | Total revenue, AOV, order count, and % distribution per payment method |
| `flagged_orders` | Orders where discount > 30% or shipping > 10% of order amount — nulls treated as zero |
| `seasonal_patterns` | Monthly trends, QoQ growth, best/worst month, coefficient of variation |
| `daily_revenue` | Daily revenue totals for a configurable date window |


## Project variables

| Variable | Default | Used in |
|---|---|---|
| `start_date` | `2024-01-01` | `daily_revenue` |
| `end_date` | `2024-12-31` | `daily_revenue` |
| `tier_high_value` | `1000` | `customer_segments` |
| `tier_medium_value` | `500` | `customer_segments` |
| `flag_discount_threshold` | `0.30` | Silver `sales_fact` flags |
| `flag_shipping_pct` | `0.10` | Silver `sales_fact` flags |
| `sk_delimiter` | `\|\|` | `generate_surrogate_key` |


## Testing

Built-in dbt tests (`unique`, `not_null`, `accepted_values`) are declared in each
layer's `schema.yml`. The `dbt_utils` package adds numeric range validation.

Seventeen custom generic tests in `tests/generic/` cover production failure modes
including duplicate surrogate keys, orphaned foreign keys, fan-out from non-unique
joins, silent null regressions, data loss between Bronze and Silver, composite grain
uniqueness on Gold models, and model freshness.
