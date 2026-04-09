# newday — dbt Project

Production-grade dbt project answering 7 analytical questions over a
sales dataset using a **Bronze → Silver → Gold** medallion architecture
on Snowflake.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  RAW  (Snowflake schema)                                            │
│  CSV files loaded as tables: sales_fact, customer, product,         │
│  product_category                                                   │
└──────────────────────┬──────────────────────────────────────────────┘
                       │  source()
┌──────────────────────▼──────────────────────────────────────────────┐
│  BRONZE  (view)                                                      │
│  brz_sales_fact · brz_customers · brz_products · brz_product_category│
│  Purpose: mirror raw source + attach _loaded_at audit stamp          │
└──────────────────────┬──────────────────────────────────────────────┘
                       │  ref()
┌──────────────────────▼──────────────────────────────────────────────┐
│  SILVER  (incremental table, merge strategy)                         │
│  slv_sales_fact · slv_customers · slv_products · slv_product_category│
│  slv_sales_enriched (view — central join)                            │
│  Purpose: type casting, surrogate/hash keys, deduplication,          │
│           null-safety, business flags, _processed_at timestamp        │
└──────────────────────┬──────────────────────────────────────────────┘
                       │  ref()
┌──────────────────────▼──────────────────────────────────────────────┐
│  GOLD  (table)                                                       │
│  Q1 gld_revenue_by_category_monthly                                  │
│  Q2 gld_revenue_edge_cases                                           │
│  Q3 gld_customer_segments                                            │
│  Q4 gld_payment_analysis                                             │
│  Q5 gld_flagged_orders                                               │
│  Q6 gld_seasonal_patterns                                            │
│  Q7 gld_daily_revenue                                                │
│  Purpose: business-ready aggregations + _refreshed_at timestamp      │
└─────────────────────────────────────────────────────────────────────┘
```

### Key design decisions

| Concern | Decision |
|---|---|
| Surrogate keys | MD5 hash via `generate_surrogate_key` macro — deterministic, portable, auditable |
| Null handling | `discount_applied` and `shipping_cost` coalesced → 0 in Silver; `_was_null` boolean columns preserve origin |
| Incrementality | Silver models use `incremental_strategy = merge` on the surrogate key; Bronze is always a view so no state is held there |
| Thresholds | All business thresholds (tier levels, flag percentages) live in `dbt_project.yml` vars — no magic numbers in SQL |
| Schema routing | `generate_schema_name` macro routes each layer to `BRONZE`, `SILVER`, `GOLD` (always clean — no env suffixes) |
| Date filtering | `date_range_filter` macro accepts `--vars` overrides at run time — no model edits needed to change the window |

---

## Prerequisites

| Tool | Version |
|---|---|
| Python | 3.8 + |
| dbt-core | >= 1.6.0 |
| dbt-snowflake | >= 1.6.0 |
| Snowflake account | Any edition |

---

## Step 1 — Snowflake setup

Open a Snowflake worksheet and run the following once.  Swap in your
own values for `<YOUR_PASSWORD>` and warehouse sizing.

```sql
-- 1a. Create a dedicated role and warehouse
use role accountadmin;

create role if not exists DEVELOPER;
create warehouse if not exists compute_wh
    warehouse_size = 'x-small'
    auto_suspend   = 60
    auto_resume    = true;

grant usage on warehouse compute_wh to role DEVELOPER;

-- 1b. Create databases
create database if not exists newday_dev;
create database if not exists analytics;

-- 1c. Create the RAW schema and load source tables
create schema if not exists newday_dev.raw;

-- 1d. Load each CSV as a Snowflake stage + COPY INTO
--     (see Step 2 for the Snowflake UI file-upload path)

-- 1e. Create a service user for dbt
create user if not exists dbt_user
    password      = '<YOUR_PASSWORD>'
    default_role  = DEVELOPER
    must_change_password = false;

grant role DEVELOPER to user dbt_user;
grant all on database newday_dev to role DEVELOPER;
grant all on database analytics      to role DEVELOPER;
```

---

## Step 2 — Load CSV files into Snowflake (UI steps)

1. In the Snowflake UI, navigate to **Data → Databases → NEWDAY_DEV → RAW**.
2. Click **+ Table → Load Data**.
3. For each CSV file (`sales_fact.csv`, `customer.csv`, `product.csv`,
   `product_category.csv`):
   - Upload the file.
   - Set table name to match the source name exactly (e.g. `SALES_FACT`).
   - Let Snowflake auto-detect column types.
   - Click **Load**.
4. Confirm row counts match expectations (sales_fact: 100, customer: 65,
   product: 35, product_category: 35).

---

## Step 3 — dbt Core local setup

```bash
# Clone the project
git clone <your-repo-url>
cd newday

# Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

# Install dbt
pip install dbt-snowflake>=1.6.0

# Copy profiles template to the dbt home directory
mkdir -p ~/.dbt
cp profiles.yml ~/.dbt/profiles.yml
# Edit ~/.dbt/profiles.yml and fill in your Snowflake credentials
# OR set environment variables (recommended for CI):
export SNOWFLAKE_ACCOUNT="xy12345.us-east-1"
export SNOWFLAKE_USER="dbt_user"
export SNOWFLAKE_PASSWORD="<your_password>"
export SNOWFLAKE_ROLE="DEVELOPER"
export SNOWFLAKE_DATABASE="NEWDAY_DEV"
export SNOWFLAKE_WAREHOUSE="COMPUTE_WH"

# Install dbt packages
dbt deps

# Verify connection
dbt debug
```

---

## Step 4 — dbt Cloud setup (UI steps)

1. Log in to [cloud.getdbt.com](https://cloud.getdbt.com).
2. **Account Settings → Connections → New Connection**
   - Type: Snowflake
   - Fill in account, database, warehouse, role.
3. **Projects → New Project**
   - Connect to your Git repository.
   - Set the project subdirectory if needed.
4. **Environments → New Environment**
   - Name: `Development`
   - dbt version: 1.6 or higher
   - Schema: `RAW`
5. **Credentials** — add your Snowflake username + password
   (or use key-pair auth for production).
6. **Jobs → New Job** (for scheduled production runs)
   - Commands:
     ```
     dbt deps
     dbt source freshness
     dbt build --target prod
     ```
   - Schedule: daily at 06:00 UTC (or match your data load cadence).

---

## Step 5 — Run the project

### Full build (all layers)
```bash
dbt build
```

### Layer by layer (useful for debugging)
```bash
dbt run  --select tag:bronze          # Views only — near-instant
dbt test --select tag:bronze

dbt run  --select tag:silver
dbt test --select tag:silver

dbt run  --select tag:gold
dbt test --select tag:gold
```

### Individual questions
```bash
dbt run --select gld_revenue_by_category_monthly   # Q1
dbt run --select gld_revenue_edge_cases            # Q2
dbt run --select gld_customer_segments             # Q3
dbt run --select gld_payment_analysis              # Q4
dbt run --select gld_flagged_orders                # Q5
dbt run --select gld_seasonal_patterns             # Q6
dbt run --select gld_daily_revenue                 # Q7
```

### Q7 — override the date range at run time
```bash
dbt run --select gld_daily_revenue \
        --vars '{"start_date": "2024-06-01", "end_date": "2024-06-30"}'
```

### Override tier thresholds without touching SQL
```bash
dbt run --select gld_customer_segments \
        --vars '{"tier_high_value": 1500, "tier_medium_value": 750}'
```

---

## Step 6 — Run tests

```bash
# All tests across all layers
dbt test

# Tests for a specific model
dbt test --select slv_sales_fact
dbt test --select gld_flagged_orders

# Source freshness check
dbt source freshness
```

---

## Step 7 — Generate and view documentation

```bash
dbt docs generate
dbt docs serve       # opens http://localhost:8080
```

In the dbt Cloud UI: **Documentation** tab → auto-generated after every
job run when `dbt docs generate` is included in the job commands.

---

## Project variables reference

| Variable | Default | Description |
|---|---|---|
| `start_date` | `2024-01-01` | Lower bound for `gld_daily_revenue` (Q7) |
| `end_date` | `2024-12-31` | Upper bound for `gld_daily_revenue` (Q7) |
| `tier_high_value` | `1000` | Min lifetime spend for "High Value" tier (Q3) |
| `tier_medium_value` | `500` | Min lifetime spend for "Medium Value" tier (Q3) |
| `flag_discount_threshold` | `0.30` | Discount fraction that triggers a review flag (Q5) |
| `flag_shipping_pct` | `0.10` | Shipping-to-order-value ratio that triggers a flag (Q5) |
| `sk_delimiter` | `\|\|` | Separator used inside the hash key concatenation |

---

## Macro reference

| Macro | File | Description |
|---|---|---|
| `generate_surrogate_key(fields)` | `macros/generate_surrogate_key.sql` | MD5 hash key from one or more columns |
| `safe_divide(num, den, default)` | `macros/safe_divide.sql` | Null-safe division; returns `default` when denominator is 0 or NULL |
| `date_range_filter(col, start, end)` | `macros/date_range_filter.sql` | Emits a WHERE predicate for an inclusive date window |
| `assert_date_range_valid(s, e)` | `macros/date_range_filter.sql` | Compile-time error if start > end |
| `generate_schema_name(name, node)` | `macros/generate_schema_name.sql` | Routes layers to correct Snowflake schemas |

---

## Custom generic tests reference

| Test | File | Description |
|---|---|---|
| `assert_positive_amount` | `tests/generic/assert_positive_amount.sql` | Fails if column <= 0 |
| `assert_valid_fraction` | `tests/generic/assert_valid_fraction.sql` | Fails if column outside [0, 1] |
| `assert_no_future_dates` | `tests/generic/assert_no_future_dates.sql` | Fails if date column is in the future |

---

## Troubleshooting

**`dbt debug` fails with "Invalid account"**
Make sure `SNOWFLAKE_ACCOUNT` is in the format `<orgname>-<accountname>` or
`<locator>.<region>` (e.g. `xy12345.us-east-1`).

**Silver incremental model not picking up new rows**
Run with `--full-refresh` once to rebuild the Silver table from scratch:
```bash
dbt run --select tag:silver --full-refresh
```

**`generate_surrogate_key` not found**
Confirm `dbt deps` has been run and `dbt_project.yml` has `macro-paths: ["macros"]`.

**Tests failing on `assert_valid_fraction` for discount_applied**
Check whether raw source data contains discount values > 1 (e.g. `1.10`
instead of `0.10`).  Investigate with:
```sql
select discount_applied from newday_dev.raw.sales_fact
where try_cast(discount_applied as float) > 1;
```
