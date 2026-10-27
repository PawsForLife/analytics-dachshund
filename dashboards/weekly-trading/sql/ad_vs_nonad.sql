-- Dataset: ad_vs_nonad
-- Title: AD vs non-AD orders
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: AOV, items per order, categories per order, order share and revenue share for AD vs non-AD orders this week, with the AD metric's movement vs LW and vs the 12-week average. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH rep AS (SELECT week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT k, DATE_SUB(rep.e, INTERVAL 7 * k + 6 DAY) AS ws, DATE_SUB(rep.e, INTERVAL 7 * k DAY) AS we
  FROM rep, UNNEST(GENERATE_ARRAY(0, 13)) AS k
  UNION ALL
  SELECT -1, week_start_date, week_end_date FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE
),
o AS (
  SELECT w.k, o.order_id, o.customer_id, o.order_type, o.is_auto_delivery_order AS ad, o.auto_delivery_order_cohort_complete AS adc,
    o.product_revenue_complete_excl_gst AS rev, o.product_margin_complete_excl_gst AS pm
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.order_created_date >= (SELECT MIN(ws) FROM wk)
),
b AS (
  SELECT order_id, SUM(quantity_complete) AS items, COUNT(DISTINCT category_description) AS cats
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date >= (SELECT MIN(ws) FROM wk)
  GROUP BY 1
),
ob AS (SELECT o.*, IFNULL(b.items, 0) AS items, IFNULL(b.cats, 0) AS cats FROM o LEFT JOIN b USING (order_id))
,
wv AS (
  SELECT k,
    SAFE_DIVIDE(SUM(IF(ad, rev, 0)), COUNTIF(ad)) AS aov_a, SAFE_DIVIDE(SUM(IF(NOT ad, rev, 0)), COUNTIF(NOT ad)) AS aov_n,
    SAFE_DIVIDE(SUM(IF(ad, items, 0)), COUNTIF(ad)) AS ipo_a, SAFE_DIVIDE(SUM(IF(NOT ad, items, 0)), COUNTIF(NOT ad)) AS ipo_n,
    SAFE_DIVIDE(SUM(IF(ad, cats, 0)), COUNTIF(ad)) AS cpo_a, SAFE_DIVIDE(SUM(IF(NOT ad, cats, 0)), COUNTIF(NOT ad)) AS cpo_n,
    SAFE_DIVIDE(COUNTIF(ad), COUNT(*)) * 100 AS os_a, SAFE_DIVIDE(COUNTIF(NOT ad), COUNT(*)) * 100 AS os_n,
    SAFE_DIVIDE(SUM(IF(ad, rev, 0)), SUM(rev)) * 100 AS rs_a, SAFE_DIVIDE(SUM(IF(NOT ad, rev, 0)), SUM(rev)) * 100 AS rs_n
  FROM ob WHERE k BETWEEN 0 AND 12 GROUP BY 1
),
lng AS (
  SELECT k, m.* FROM wv, UNNEST([
    STRUCT('aov' AS metric, 'AOV' AS label, '$' AS unit, 1 AS sort, aov_a AS a, aov_n AS n),
    STRUCT('items_per_order', 'Items / order', 'n', 2, ipo_a, ipo_n),
    STRUCT('categories_per_order', 'Categories / order', 'n', 3, cpo_a, cpo_n),
    STRUCT('order_share', 'Order share', 'pct', 4, os_a, os_n),
    STRUCT('revenue_share', 'Revenue share', 'pct', 5, rs_a, rs_n)]) m
),
agg AS (
  SELECT metric, ANY_VALUE(label) AS label, ANY_VALUE(unit) AS unit, ANY_VALUE(sort) AS sort,
    MAX(IF(k = 0, a, NULL)) AS ad, MAX(IF(k = 0, n, NULL)) AS nonad, MAX(IF(k = 1, a, NULL)) AS ad_lw, AVG(IF(k BETWEEN 1 AND 12, a, NULL)) AS ad_l13w
  FROM lng GROUP BY 1
)
SELECT metric, label, unit, sort,
  ROUND(ad, 4) AS ad, ROUND(nonad, 4) AS nonad,
  ROUND(IF(unit = 'pct', ad - ad_lw, SAFE_DIVIDE(ad, ad_lw) - 1), 4) AS ad_d_lw,
  ROUND(IF(unit = 'pct', ad - ad_l13w, SAFE_DIVIDE(ad, ad_l13w) - 1), 4) AS ad_d_l13w,
  CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM agg ORDER BY sort
