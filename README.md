# Retail Promotions \& Performance Analytics: Monthly Retailer Pack and Promo Compliance

An end-to-end retail insights portfolio project built on the **dunnhumby – The Complete Journey** dataset: **2.6M** purchase lines from 2,500 loyalty-card households over 102 weeks. It combines a BigQuery SQL pipeline, price and volume driver analysis, and a promotional execution scoring model, delivered through a two-page Tableau dashboard suite designed for retailer account teams and field teams.

## Quick Links \& Navigation

* **Tableau Dashboard 1, Retailer Performance Pack:** [View Live on Tableau Public](https://public.tableau.com/app/profile/sam.rose.maria.selvam/viz/RetailerPerformancePack/Dashboard2)
* **Tableau Dashboard 2, Promo Compliance \& Execution:** [View Live on Tableau Public](https://public.tableau.com/app/profile/sam.rose.maria.selvam/viz/PromoComplianceandExecution/Dashboard3?publish=yes)
* **BigQuery SQL Pipeline:** `sql/retail_insights_pipeline.sql`
* **Source Data:** dunnhumby Source Files, *The Complete Journey*

\---

## Dashboard Preview

### Dashboard 1: Retailer Performance Pack

<img width="1397" height="1055" alt="Screenshot 2026-11-17 195136" src="https://github.com/user-attachments/assets/01385014-3d07-46a9-8fab-82941650f76e" />


### Dashboard 2: Promo Compliance \& Execution

<img width="1385" height="1052" alt="Screenshot 2026-11-17 195318" src="https://github.com/user-attachments/assets/a5103eea-3d0b-4462-80fb-73d205a175f7" />


\---


## Technical Architecture \& Workflow

1. **BigQuery Data Warehouse:** Multi-table joins across transactions, product catalogue, and promotion calendar; a retail 4-week period calendar for like-for-like comparison; a cleaned transaction view used as the single source of truth; price and volume decomposition tables; promo baseline and lift tables.
2. **SQL-Generated Insight Text:** Rule-based Key Finding and Recommended Action text written in SQL for every period, so the dashboard displays commentary rather than just numbers.
3. **Tableau Executive Dashboards:** Parameter-driven period and promotion-type selectors, KPI strips, driver charts, store scatter and ranking views, and a metric definitions footer.

\---

## Dataset Overview

|Table used|What it holds|
|-|-|
|`transaction_data`|Every purchase line: household, basket, product, store, week, quantity, sales value, discounts|
|`product`|Department, commodity, brand (private or national label)|
|`causal_data`|Whether a product was on an in-store display or in the weekly mailer, by store and week|

### Key facts that shape the analysis:

* Time is stored as `week_no` 1 to 102, not calendar dates.
* The data covers a sample of 2,500 households, so all sales figures are sample sales, not total store sales.
* Discounts are stored as negative values; pre-discount value is recovered by adding them back.
* The other source tables (demographics, campaigns, coupons) were loaded but are not used in these two modules.

\---

## Methodology: Module 1 – Monthly Retailer Performance Pack

* **Calendar:** Weeks 1 to 52 are Year 1 (last year) and weeks 53 to 102 are Year 2 (this year). Weeks are grouped into 4-week periods. Year 2 has only 50 weeks, so Period 13 is partial and like-for-like views use Periods 1 to 12.
* **Plan:** Simulated as last year plus 3% (an adjustable parameter in the SQL), used to show gap to plan.

### Price and Volume Decomposition:

```text
volume_effect = (units_TY - units_LY) \* price_per_unit_LY
price_effect  = (price_per_unit_TY - price_per_unit_LY) \* units_TY
volume_effect + price_effect = sales_TY - sales_LY
```

The identity above is checked in SQL and reconciles to a difference of `0.00`, so the drivers always add up to the total change.

### Key Finding Logic (rule-based, generated in SQL):

```text
+-----------------------------------+-----------------------------------+
| Key Finding Rules (Volume vs Price)                                   |
+-----------------------------------+-----------------------------------+
| \[1] Volume up, Price up           --> Healthy growth                  |
| \[2] Volume up, Price down         --> Volume-led, check discounting   |
| \[3] Volume down, Price up         --> Held up by price, demand weak   |
| \[4] Volume down, Price down       --> Broad weakness                  |
+-----------------------------------+-----------------------------------+
```

The Recommended Action text names the best and worst department by dollar change versus last year and states whether the period is ahead of or behind plan.

\---

## Methodology: Module 2 – Promotional Compliance \& Execution

No store audit data exists in the dataset, so compliance is inferred from sales uplift: if a product was featured but sold no more than usual, the feature was probably not executed properly.

* **Normal selling speed for each product in each store:**
`baseline_units_per_week = non-promo units / non-promo weeks`
* **How much extra did the promotion sell?**
`lift_index = units sold in promo week / baseline_units_per_week` *(1.0 = no lift, 2.0 = double normal sales)*
* **Units the store fell short of the chain-average result:**
`missed_units = MAX(baseline_units \* chain_lift - promo_units, 0)`

Only product-store pairs with enough normal sales to compare against (at least 20 non-promo units) are evaluated. Store verdicts use totals across many lines, because single product-store-weeks are noisy in a household sample.

### Store Verdict Rules (Hierarchical CASE Evaluation in SQL):

```text
+-----------------------------------+-----------------------------------+
| Store Verdict Progression                                             |
+-----------------------------------+-----------------------------------+
| \[1] Too few lines to judge        --> fewer than 30 promo lines       |
| \[2] No lift (execution gap)       --> store lift <= 1.0               |
| \[3] Under-delivering              --> store lift < 70% of chain lift  |
| \[4] On track                      --> Default                         |
+-----------------------------------+-----------------------------------+
```

\---

## Data Validation \& Analytical Rigor

### Checks run before any dashboard was built:

* Row-count reconciliation across all loaded tables (`transaction_data`: 2,595,732 rows; `causal_data`: 36,786,524 rows; `product`: 92,353 rows).
* Time-range check: week numbers 1 to 102, expected store and household counts.
* Discount sign check: confirmed discounts are negative before using them to rebuild pre-discount sales.
* Driver reconciliation: price effect plus volume effect equals total change versus last year (difference `0.00`).

### Data traps handled deliberately:

* **Baskets are not additive across departments.** One basket can contain several departments, so spend per basket is shown at department level only.
* **Ratios are recalculated from totals, never averaged.** Lift, price per unit, and percentage change are rebuilt from summed units and sales in Tableau.
* **Partial period excluded.** Period 13 has only two weeks in Year 2, so it is left out of like-for-like views.
* **Sparse sample handled.** Promo verdicts are aggregated per store with a minimum line count instead of judging single weeks.

\---

## Tableau Dashboard Suite Progress Tracker

**Interactive Tableau Workbooks:**



* **Dashboard 1: [Retailer Performance Pack](https://public.tableau.com/app/profile/sam.rose.maria.selvam/viz/RetailerPerformancePack/Dashboard2) (Completed ✅)** — Period selector (1 to 12), KPI strip (sales, vs last year, vs plan, units, price per unit), sales trend versus last year and plan, price versus volume drivers by department, department scorecard, and the Key Finding and Recommended Action panel.
* **Dashboard 2: [Dashboard 2: Promo Compliance \& Execution](https://public.tableau.com/app/profile/sam.rose.maria.selvam/viz/PromoComplianceandExecution/Dashboard3?publish=yes) (Completed ✅)** — Promotion-type selector (all, display only, mailer only, display plus mailer), KPI strip, store verdict distribution, store scatter of lift versus volume, top 15 stores below chain performance, lift by display location and flyer position, and lift trend over time.
* **Dashboard 3: Stock-Out \& Availability Alerts (Planned)** — Likely out-of-stock detection from zero-sales weeks in regularly selling product-store pairs, prioritising promoted weeks.

\---

## Limitations \& Assumptions

* Promo compliance and any availability conclusions are inferred from sales, not measured by audit or stock data.
* Figures come from a 2,500-household sample, so they describe sample sales and not total store sales.
* The plan is a simulated target (last year plus 3%), not a real business plan.
* The lift baseline assumes a product's non-promo weeks represent its normal selling speed.

\---

## Reproduction Steps

1. **BigQuery Setup:** Create a dataset named `retail_data` and load the source CSVs as tables named `transaction_data`, `product`, `causal_data`, and the others. `causal_data` is very large; if it exceeds the console upload limit, keep only rows where a display or mailer feature exists, or load it with the `bq` command line or a Cloud Storage bucket.
2. **SQL Pipeline:** Run `sql/retail_insights_pipeline.sql` in order (Part 1, Part 2, Part 3). Each statement can be run on its own.
3. **Export for Tableau:** Export `m1_period_dept`, `m1_commentary`, `m2_store_scorecard`, `m2_feature_effectiveness`, and `m2_period_trend` as CSV.
4. **Tableau Public:** Connect each CSV as a data source, create the `p_Period` and `p_Feature` parameters, and build the calculated fields used by the sheets (lifts and percentage changes are recalculated from summed values).

\---

**Built with:** BigQuery SQL, Tableau Public

### Author

**Sam Rose M** — Data Analyst | [LinkedIn Profile](https://www.linkedin.com/in/sam-rose-m-57158027a/)


