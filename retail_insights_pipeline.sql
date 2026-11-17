-- =====================================================================
-- DUNNHUMBY RETAIL ANALYTICS - UNIFIED SQL PIPELINE
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0A. SANITY CHECKS & DATA PROFILING
-- ---------------------------------------------------------------------

-- Row counts per table
SELECT 'transaction_data' AS tbl, COUNT(*) AS n FROM retail_data.transaction_data UNION ALL
SELECT 'product',          COUNT(*) FROM retail_data.product         UNION ALL
SELECT 'hh_demographic', COUNT(*) FROM retail_data.hh_demographic UNION ALL
SELECT 'campaign_table', COUNT(*) FROM retail_data.campaign_table UNION ALL
SELECT 'campaign_desc',  COUNT(*) FROM retail_data.campaign_desc  UNION ALL
SELECT 'coupon',         COUNT(*) FROM retail_data.coupon         UNION ALL
SELECT 'causal_data',    COUNT(*) FROM retail_data.causal_data    UNION ALL
SELECT 'coupon_redempt', COUNT(*) FROM retail_data.coupon_redempt;

-- Time range
SELECT MIN(day) AS min_day, MAX(day) AS max_day,
       MIN(week_no) AS min_wk, MAX(week_no) AS max_wk,
       COUNT(DISTINCT store_id) AS stores,
       COUNT(DISTINCT household_key) AS households,
       COUNT(DISTINCT basket_id) AS baskets
FROM retail_data.transaction_data;

-- Sign convention of discounts 
SELECT COUNTIF(retail_disc < 0) AS retail_disc_neg,
       COUNTIF(retail_disc > 0) AS retail_disc_pos,
       COUNTIF(coupon_match_disc < 0) AS cmatch_neg,
       COUNTIF(coupon_match_disc > 0) AS cmatch_pos,
       COUNTIF(quantity = 0) AS qty_zero,
       COUNTIF(sales_value <= 0) AS sales_zero_or_neg
FROM retail_data.transaction_data;


-- ---------------------------------------------------------------------
-- 0B. CALENDAR DIMENSION
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE retail_data.dim_calendar AS
SELECT
  week_no,
  IF(week_no <= 52, 1, 2)                                      AS year_no,
  IF(week_no <= 52, week_no, week_no - 52)                     AS week_in_year,
  CAST(CEIL(IF(week_no <= 52, week_no, week_no - 52) / 4) AS INT64) AS period_no,
  CAST(CEIL(IF(week_no <= 52, week_no, week_no - 52) / 4) AS INT64) <= 12 AS is_lfl
FROM UNNEST(GENERATE_ARRAY(1, 102)) AS week_no;


-- ---------------------------------------------------------------------
-- 0C. CLEAN TRANSACTION VIEW (Single source of truth)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW retail_data.v_txn AS
SELECT
  t.household_key,
  t.basket_id,
  t.day,
  t.week_no,
  t.store_id,
  t.product_id,
  t.quantity,
  t.sales_value                                         AS net_sales,
  t.retail_disc,
  t.coupon_match_disc,
  t.coupon_disc,
  t.sales_value - t.retail_disc - t.coupon_match_disc   AS base_sales,
  (t.retail_disc <> 0 OR t.coupon_match_disc <> 0)      AS is_promo_line,
  p.department,
  p.commodity_desc,
  p.sub_commodity_desc,
  p.brand,
  p.manufacturer,
  c.year_no,
  c.period_no,
  c.week_in_year,
  c.is_lfl
FROM retail_data.transaction_data AS t
JOIN retail_data.product          AS p ON p.product_id = t.product_id
JOIN retail_data.dim_calendar     AS c ON c.week_no    = t.week_no
WHERE t.quantity > 0
  AND t.sales_value > 0
  AND p.department IN ('GROCERY', 'DRUG GM', 'PRODUCE', 'COSMETICS', 'NUTRITION', 
    'MEAT', 'MEAT-PCKGD', 'DELI', 'PASTRY', 'FLORAL', 
    'SEAFOOD-PCKGD', 'SPIRITS', 'SEAFOOD', 'FROZEN GROCERY', 'DAIRY DELI'
);


-- =====================================================================
-- MODULE 1: MONTHLY RETAILER PERFORMANCE REVIEW
-- =====================================================================
CREATE OR REPLACE TABLE retail_data.m1_period_dept AS
WITH params AS (SELECT 0.03 AS plan_growth),
agg AS (
  SELECT
    year_no, period_no, is_lfl, department,
    SUM(net_sales)                                  AS sales,
    SUM(base_sales)                                 AS base_sales,
    SUM(quantity)                                   AS units,
    COUNT(DISTINCT basket_id)                       AS baskets,
    COUNT(DISTINCT household_key)                   AS households,
    SUM(IF(is_promo_line, net_sales, 0))            AS promo_sales
  FROM retail_data.v_txn
  GROUP BY 1, 2, 3, 4
)
SELECT
  ty.period_no,
  ty.is_lfl,
  ty.department,

  ty.sales                                                   AS sales_ty,
  ly.sales                                                   AS sales_ly,
  SAFE_DIVIDE(ty.sales - ly.sales, ly.sales)                 AS sales_yoy,

  ly.sales * (1 + p.plan_growth)                             AS sales_plan,
  ty.sales - ly.sales * (1 + p.plan_growth)                  AS gap_to_plan,

  ty.units                                                   AS units_ty,
  ly.units                                                   AS units_ly,
  SAFE_DIVIDE(ty.units - ly.units, ly.units)                 AS units_yoy,

  SAFE_DIVIDE(ty.sales, ty.units)                            AS price_unit_ty,
  SAFE_DIVIDE(ly.sales, ly.units)                            AS price_unit_ly,

  (ty.units - ly.units) * SAFE_DIVIDE(ly.sales, ly.units)    AS volume_effect,
  (SAFE_DIVIDE(ty.sales, ty.units) - SAFE_DIVIDE(ly.sales, ly.units)) * ty.units
                                                             AS price_effect,

  ty.baskets                                                 AS baskets_ty,
  ly.baskets                                                 AS baskets_ly,
  SAFE_DIVIDE(ty.sales, ty.baskets)                          AS spend_per_basket_ty,
  SAFE_DIVIDE(ly.sales, ly.baskets)                          AS spend_per_basket_ly,

  SAFE_DIVIDE(ty.promo_sales, ty.sales)                      AS promo_share_ty,
  SAFE_DIVIDE(ly.promo_sales, ly.sales)                      AS promo_share_ly,
  SAFE_DIVIDE(ty.base_sales - ty.sales, ty.base_sales)       AS discount_depth_ty,
  SAFE_DIVIDE(ly.base_sales - ly.sales, ly.base_sales)       AS discount_depth_ly
FROM agg AS ty
LEFT JOIN agg AS ly
  ON  ly.year_no   = 1
  AND ly.period_no = ty.period_no
  AND ly.department = ty.department
CROSS JOIN params AS p
WHERE ty.year_no = 2;


-- =====================================================================
-- Monthly period commentary
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE retail_data.m1_commentary AS
WITH tot AS (
  SELECT
    period_no,
    SUM(sales_ty)      AS sales_ty,
    SUM(sales_ly)      AS sales_ly,
    SUM(sales_plan)    AS sales_plan,
    SUM(volume_effect) AS volume_effect,
    SUM(price_effect)  AS price_effect
  FROM retail_data.m1_period_dept
  WHERE is_lfl AND sales_ly IS NOT NULL
  GROUP BY 1
),
dept_change AS (
  SELECT period_no, department, sales_ty - sales_ly AS chg
  FROM retail_data.m1_period_dept
  WHERE is_lfl AND sales_ly IS NOT NULL
),
ranked AS (
  SELECT
    period_no, department, chg,
    ROW_NUMBER() OVER (PARTITION BY period_no ORDER BY chg DESC) AS rn_best,
    ROW_NUMBER() OVER (PARTITION BY period_no ORDER BY chg ASC)  AS rn_worst
  FROM dept_change
),
joined AS (
  SELECT
    t.*,
    SAFE_DIVIDE(t.sales_ty - t.sales_ly, t.sales_ly)     AS yoy,
    SAFE_DIVIDE(t.sales_ty - t.sales_plan, t.sales_plan) AS vs_plan,
    b.department AS best_dept,  b.chg AS best_chg,
    w.department AS worst_dept, w.chg AS worst_chg
  FROM tot AS t
  JOIN ranked AS b ON b.period_no = t.period_no AND b.rn_best  = 1
  JOIN ranked AS w ON w.period_no = t.period_no AND w.rn_worst = 1
)
SELECT
  period_no,
  sales_ty, sales_ly, sales_plan, yoy, vs_plan,
  volume_effect, price_effect,
  best_dept, best_chg, worst_dept, worst_chg,

  CONCAT('Period ', CAST(period_no AS STRING), ': sales ',
         IF(yoy >= 0, '+', ''), CAST(ROUND(yoy * 100, 1) AS STRING), '% vs last year and ',
         IF(vs_plan >= 0, '+', ''), CAST(ROUND(vs_plan * 100, 1) AS STRING), '% vs plan') AS headline,

  CASE
    WHEN volume_effect > 0 AND price_effect > 0
      THEN 'Healthy growth: shoppers bought more units and the average price per unit also rose.'
    WHEN volume_effect > 0 AND price_effect <= 0
      THEN 'Growth is volume-led but price per unit fell: check whether discounting is buying the extra volume.'
    WHEN volume_effect <= 0 AND price_effect > 0
      THEN 'Sales are held up by price, not demand: fewer units were sold, so shoppers are buying less.'
    ELSE 'Both units and price per unit are down: broad weakness across the range.'
  END AS key_finding,

  CONCAT(
    'Protect momentum in ', best_dept, ' (', IF(best_chg >= 0, '+', ''),
    CAST(ROUND(best_chg) AS STRING), ' USD vs LY). Prioritise recovery in ', worst_dept,
    ' (', IF(worst_chg >= 0, '+', ''), CAST(ROUND(worst_chg) AS STRING), ' USD vs LY).',
    IF(sales_ty < sales_plan,
        CONCAT(' Behind plan by ', CAST(ROUND(sales_plan - sales_ty) AS STRING),
               ' USD: agree catch-up actions with the account manager.'),
        ' Ahead of plan: confirm what is working and lock it in for next period.')
  ) AS recommended_action
FROM joined
ORDER BY period_no;


-- =====================================================================
-- MODULE 2: TRADE PROMOTION & EXECUTION ANALYSIS
-- ---------------------------------------------------------------------

-- Creating Display Dimension table
CREATE OR REPLACE TABLE retail_data.dim_display AS
SELECT * FROM UNNEST([
  STRUCT('0' AS display_code, 'Not on display' AS display_desc),
  STRUCT('1', 'Store front'),
  STRUCT('2', 'Store rear'),
  STRUCT('3', 'Front end cap'),
  STRUCT('4', 'Mid-aisle end cap'),
  STRUCT('5', 'Rear end cap'),
  STRUCT('6', 'Side-aisle end cap'),
  STRUCT('7', 'In-aisle'),
  STRUCT('9', 'Secondary location display'),
  STRUCT('A', 'In-shelf')
]);

-- Creating mailer dimension
CREATE OR REPLACE TABLE retail_data.dim_mailer AS
SELECT * FROM UNNEST([
  STRUCT('0' AS mailer_code, 'Not on ad' AS mailer_desc),
  STRUCT('A', 'Interior page feature'),
  STRUCT('C', 'Interior page line item'),
  STRUCT('D', 'Front page feature'),
  STRUCT('F', 'Back page feature'),
  STRUCT('H', 'Wrap front feature'),
  STRUCT('J', 'Wrap interior coupon'),
  STRUCT('L', 'Wrap back feature'),
  STRUCT('P', 'Interior page coupon'),
  STRUCT('X', 'Free on interior page'),
  STRUCT('Z', 'Free on front page, back page or wrap')
]);

-- Weekly sales per product per store (fact sales)
CREATE OR REPLACE TABLE retail_data.f_sales_psw AS
SELECT
  product_id, store_id, week_no,
  SUM(quantity)  AS units,
  SUM(net_sales) AS sales
FROM retail_data.v_txn
GROUP BY 1, 2, 3;

-- The promo calendar
CREATE OR REPLACE TABLE retail_data.f_promo_psw AS
WITH c AS (
  SELECT
    product_id, store_id, week_no,
    COALESCE(TRIM(CAST(display AS STRING)), '0') AS display_code,
    COALESCE(TRIM(CAST(mailer  AS STRING)), '0') AS mailer_code
  FROM retail_data.causal_data
),
d AS (
  SELECT
    product_id, store_id, week_no,
    MAX(display_code) AS display_code,
    MAX(mailer_code)  AS mailer_code
  FROM c
  WHERE display_code <> '0' OR mailer_code <> '0'
  GROUP BY 1, 2, 3
)
SELECT
  product_id, store_id, week_no, display_code, mailer_code,
  display_code <> '0' AS has_display,
  mailer_code  <> '0' AS has_mailer,
  CASE
    WHEN display_code <> '0' AND mailer_code <> '0' THEN 'Display + Mailer'
    WHEN display_code <> '0' THEN 'Display only'
    ELSE 'Mailer only'
  END AS feature_type
FROM d;

-- Normal week selling speed
CREATE OR REPLACE TABLE retail_data.f_baseline_ps AS
WITH tot AS (
  SELECT product_id, store_id, SUM(units) AS total_units, SUM(sales) AS total_sales
  FROM retail_data.f_sales_psw
  GROUP BY 1, 2
),
promo AS (
  SELECT
    p.product_id, p.store_id,
    COUNT(*) AS promo_weeks,
    SUM(COALESCE(s.units, 0)) AS promo_units
  FROM retail_data.f_promo_psw AS p
  LEFT JOIN retail_data.f_sales_psw AS s
    ON s.product_id = p.product_id AND s.store_id = p.store_id AND s.week_no = p.week_no
  GROUP BY 1, 2
)
SELECT
  p.product_id, p.store_id, p.promo_weeks,
  t.total_units - p.promo_units                             AS nonpromo_units,
  102 - p.promo_weeks                                       AS nonpromo_weeks,
  SAFE_DIVIDE(t.total_units - p.promo_units, 102 - p.promo_weeks) AS baseline_units_pw,
  SAFE_DIVIDE(t.total_sales, t.total_units)                 AS avg_price
FROM promo AS p
JOIN tot   AS t ON t.product_id = p.product_id AND t.store_id = p.store_id;

-- Promo lines
CREATE OR REPLACE TABLE retail_data.m2_promo_lines AS
WITH params AS (SELECT 20 AS min_nonpromo_units, 1.2 AS good_lift),
base AS (
  SELECT
    p.product_id, p.store_id, p.week_no,
    p.display_code, p.mailer_code, p.has_display, p.has_mailer, p.feature_type,
    COALESCE(s.units, 0)  AS promo_units,
    COALESCE(s.sales, 0)  AS promo_sales,
    b.baseline_units_pw,
    b.avg_price,
    SAFE_DIVIDE(COALESCE(s.units, 0), b.baseline_units_pw) AS lift_index
  FROM retail_data.f_promo_psw AS p
  JOIN retail_data.f_baseline_ps AS b
    ON b.product_id = p.product_id AND b.store_id = p.store_id
  LEFT JOIN retail_data.f_sales_psw AS s
    ON s.product_id = p.product_id AND s.store_id = p.store_id AND s.week_no = p.week_no
  CROSS JOIN params AS q
  WHERE b.nonpromo_units >= q.min_nonpromo_units
)
SELECT
  x.*,
  c.year_no, c.period_no,
  pr.department, pr.commodity_desc, pr.brand,
  x.lift_index <= 1.0 AS is_gap,
  CASE
    WHEN x.lift_index <= 1.0    THEN 'No lift'
    WHEN x.lift_index < q.good_lift THEN 'Weak lift'
    ELSE 'Good lift'
  END AS lift_band
FROM base AS x
JOIN retail_data.dim_calendar AS c  ON c.week_no = x.week_no
JOIN retail_data.product      AS pr ON pr.product_id = x.product_id
CROSS JOIN params AS q;

-- Chain-wide benchmark
CREATE OR REPLACE TABLE retail_data.m2_chain_lift AS
SELECT
  feature_type,
  COUNT(*)                                            AS n_lines,
  SAFE_DIVIDE(SUM(promo_units), SUM(baseline_units_pw)) AS chain_lift,
  SAFE_DIVIDE(COUNTIF(is_gap), COUNT(*))              AS chain_gap_rate
FROM retail_data.m2_promo_lines
GROUP BY 1;

-- Store scorecard
CREATE OR REPLACE TABLE retail_data.m2_store_scorecard AS
WITH params AS (SELECT 30 AS min_lines, 0.7 AS under_ratio),
s AS (
  SELECT
    store_id, feature_type,
    COUNT(*)                           AS n_lines,
    COUNTIF(is_gap)                    AS no_lift_lines,
    SUM(promo_units)                   AS promo_units,
    SUM(baseline_units_pw)             AS baseline_units,
    SUM(promo_sales)                   AS promo_sales,
    SAFE_DIVIDE(SUM(promo_units), SUM(baseline_units_pw)) AS store_lift
  FROM retail_data.m2_promo_lines
  GROUP BY 1, 2
)
SELECT
  s.store_id, s.feature_type, s.n_lines, s.no_lift_lines,
  SAFE_DIVIDE(s.no_lift_lines, s.n_lines) AS no_lift_rate,
  c.chain_gap_rate,
  s.promo_units, s.baseline_units, s.promo_sales,
  s.store_lift, c.chain_lift,
  SAFE_DIVIDE(s.store_lift, c.chain_lift) AS lift_vs_chain,
  GREATEST(s.baseline_units * c.chain_lift - s.promo_units, 0) AS missed_units,
  CASE
    WHEN s.n_lines < p.min_lines                    THEN 'Too few lines to judge'
    WHEN s.store_lift <= 1.0                        THEN 'No lift (execution gap)'
    WHEN SAFE_DIVIDE(s.store_lift, c.chain_lift) < p.under_ratio THEN 'Under-delivering'
    ELSE 'On track'
  END AS status
FROM s
JOIN retail_data.m2_chain_lift AS c ON c.feature_type = s.feature_type
CROSS JOIN params AS p;

-- Feature effectiveness
CREATE OR REPLACE TABLE retail_data.m2_feature_effectiveness AS
SELECT
  l.department, l.feature_type,
  COALESCE(d.display_desc, l.display_code) AS display_desc,
  COALESCE(m.mailer_desc,  l.mailer_code)  AS mailer_desc,
  COUNT(*)                                             AS n_lines,
  COUNTIF(l.is_gap)                                    AS no_lift_lines,
  SUM(l.promo_units)                                   AS promo_units,
  SUM(l.baseline_units_pw)                             AS baseline_units,
  SAFE_DIVIDE(SUM(l.promo_units), SUM(l.baseline_units_pw)) AS lift,
  SAFE_DIVIDE(COUNTIF(l.is_gap), COUNT(*))             AS no_lift_rate
FROM retail_data.m2_promo_lines AS l
LEFT JOIN retail_data.dim_display AS d ON d.display_code = l.display_code
LEFT JOIN retail_data.dim_mailer  AS m ON m.mailer_code  = l.mailer_code
GROUP BY 1, 2, 3, 4;

-- Period trend
CREATE OR REPLACE TABLE retail_data.m2_period_trend AS
SELECT
  year_no, period_no, feature_type,
  COUNT(*)                 AS n_lines,
  COUNTIF(is_gap)          AS no_lift_lines,
  SUM(promo_units)         AS promo_units,
  SUM(baseline_units_pw)   AS baseline_units,
  SAFE_DIVIDE(SUM(promo_units), SUM(baseline_units_pw)) AS lift,
  SAFE_DIVIDE(COUNTIF(is_gap), COUNT(*))               AS no_lift_rate
FROM retail_data.m2_promo_lines
GROUP BY 1, 2, 3;
