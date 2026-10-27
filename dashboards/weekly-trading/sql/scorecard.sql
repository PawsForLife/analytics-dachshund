-- Dataset: scorecard
-- Title: Commercial scorecard
-- Tab: Highlights
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reporting-week commercial metrics with last week, the average of the 12 prior weeks, 445 LY and budget levels and deltas. Reads product__customer_order, customer__customer_order_basket, inventory__product_variant_item_mapping, customer__customer_lifecycle_attributes__eod, customer__forecast_customer_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_start_date AS rws, week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    c.week_end_date = r.rwe AS is_tw,
    c.week_end_date = DATE_SUB(r.rwe, INTERVAL 7 DAY) AS is_lw,
    c.week_end_date < r.rwe AND NOT c.is_prior_year_latest_merch_complete_week AS is_p12,
    c.is_prior_year_latest_merch_complete_week AS is_ly
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.rwe, INTERVAL 84 DAY) AND r.rwe
     OR c.is_prior_year_latest_merch_complete_week = TRUE
),
o AS (
  SELECT w.we, o.order_id, o.customer_id, o.product_revenue_complete_excl_gst AS rev,
    o.product_margin_complete_excl_gst AS pm, o.net_revenue_complete_excl_gst AS nrev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
),
om AS (
  SELECT we, SUM(rev) AS rev, SUM(pm) AS pm, SUM(nrev) AS nrev,
    COUNT(DISTINCT order_id) AS orders, COUNT(DISTINCT customer_id) AS pc
  FROM o GROUP BY we
),
mp AS (
  SELECT product_variant_code, MAX(unit_of_measure_conversion) AS uom
  FROM `petcircle-warehouse-cloud.business_layer.inventory__product_variant_item_mapping`
  GROUP BY product_variant_code
),
u AS (
  SELECT o.we, SUM(b.quantity_complete * IFNULL(mp.uom, 1)) AS units
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  JOIN (SELECT DISTINCT we, order_id FROM o) o ON b.order_id = o.order_id
  LEFT JOIN mp ON b.product_variant_code = mp.product_variant_code
  WHERE b.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
  GROUP BY o.we
),
a AS (
  SELECT valid_for_date AS we, COUNT(DISTINCT IF(is_active_92, customer_id, NULL)) AS a92
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date IN (SELECT we FROM wk)
  GROUP BY valid_for_date
),
bd AS (
  SELECT SUM(f.daily_forecast_gross_product_revenue) AS rev, SUM(f.daily_forecast_product_margin) AS pm,
    SUM(f.daily_forecast_order_count) AS orders, SUM(f.daily_forecast_units_sold) AS units,
    AVG(f.daily_forecast_active_92_customer_base) AS a92
  FROM `petcircle-warehouse-cloud.business_layer.customer__forecast_customer_by_day` f
  CROSS JOIN r
  WHERE f.calendar_date BETWEEN r.rws AND r.rwe
),
m AS (
  SELECT 'product_revenue' AS k, 'Product revenue' AS label, 'Revenue' AS grp, '$' AS unit, 1 AS sort UNION ALL
  SELECT 'net_revenue', 'Net revenue', 'Revenue', '$', 2 UNION ALL
  SELECT 'product_margin', 'Product margin', 'Margin', '$', 3 UNION ALL
  SELECT 'product_margin_pct', 'Product margin %', 'Margin', 'pct', 4 UNION ALL
  SELECT 'asp', 'ASP', 'Revenue drivers', '$', 5 UNION ALL
  SELECT 'units_per_order', 'Units per order', 'Revenue drivers', 'n', 6 UNION ALL
  SELECT 'aov', 'AOV', 'Revenue drivers', '$', 7 UNION ALL
  SELECT 'orders', 'Orders', 'Revenue drivers', 'n', 8 UNION ALL
  SELECT 'units', 'Units', 'Revenue drivers', 'n', 9 UNION ALL
  SELECT 'purchasing_customers', 'Purchasing customers', 'Customers', 'n', 10 UNION ALL
  SELECT 'a92_base', 'A92 base', 'Customers', 'n', 11
),
lg AS (
  SELECT w.is_tw, w.is_lw, w.is_p12, w.is_ly, x.k, x.v
  FROM wk w
  LEFT JOIN om ON om.we = w.we
  LEFT JOIN u ON u.we = w.we
  LEFT JOIN a ON a.we = w.we,
  UNNEST([
    STRUCT('product_revenue' AS k, om.rev AS v),
    STRUCT('net_revenue', om.nrev),
    STRUCT('product_margin', om.pm),
    STRUCT('product_margin_pct', SAFE_DIVIDE(om.pm, om.rev) * 100),
    STRUCT('asp', SAFE_DIVIDE(om.rev, u.units)),
    STRUCT('units_per_order', SAFE_DIVIDE(u.units, om.orders)),
    STRUCT('aov', SAFE_DIVIDE(om.rev, om.orders)),
    STRUCT('orders', CAST(om.orders AS FLOAT64)),
    STRUCT('units', CAST(u.units AS FLOAT64)),
    STRUCT('purchasing_customers', CAST(om.pc AS FLOAT64)),
    STRUCT('a92_base', CAST(a.a92 AS FLOAT64))
  ]) x
),
bl AS (
  SELECT x.k, x.v FROM bd,
  UNNEST([
    STRUCT('product_revenue' AS k, bd.rev AS v),
    STRUCT('net_revenue', CAST(NULL AS FLOAT64)),
    STRUCT('product_margin', bd.pm),
    STRUCT('product_margin_pct', SAFE_DIVIDE(bd.pm, bd.rev) * 100),
    STRUCT('asp', SAFE_DIVIDE(bd.rev, bd.units)),
    STRUCT('units_per_order', SAFE_DIVIDE(bd.units, bd.orders)),
    STRUCT('aov', SAFE_DIVIDE(bd.rev, bd.orders)),
    STRUCT('orders', bd.orders),
    STRUCT('units', bd.units),
    STRUCT('purchasing_customers', CAST(NULL AS FLOAT64)),
    STRUCT('a92_base', bd.a92)
  ]) x
),
agg AS (
  SELECT k,
    MAX(IF(is_tw, v, NULL)) AS tw,
    MAX(IF(is_lw, v, NULL)) AS lw,
    AVG(IF(is_p12, v, NULL)) AS l13w,
    MAX(IF(is_ly, v, NULL)) AS ly
  FROM lg GROUP BY k
)
SELECT
  m.k AS metric, m.label, m.grp, m.unit, m.sort,
  ROUND(g.tw, IF(m.unit = '$', 2, 4)) AS tw,
  ROUND(g.lw, IF(m.unit = '$', 2, 4)) AS lw,
  ROUND(g.l13w, IF(m.unit = '$', 2, 4)) AS l13w,
  ROUND(g.ly, IF(m.unit = '$', 2, 4)) AS ly,
  ROUND(bl.v, IF(m.unit = '$', 2, 4)) AS bud,
  ROUND(g.tw - g.lw, IF(m.unit = '$', 2, 4)) AS d_lw,
  ROUND(g.tw - g.l13w, IF(m.unit = '$', 2, 4)) AS d_l13w,
  ROUND(g.tw - g.ly, IF(m.unit = '$', 2, 4)) AS d_ly,
  ROUND(g.tw - bl.v, IF(m.unit = '$', 2, 4)) AS d_bud,
  ROUND(SAFE_DIVIDE(g.tw, bl.v) - 1, 4) AS d_bud_pct,
  ROUND(SAFE_DIVIDE(g.tw, g.lw) - 1, 4) AS d_lw_pct,
  ROUND(SAFE_DIVIDE(g.tw, g.l13w) - 1, 4) AS d_l13w_pct,
  ROUND(SAFE_DIVIDE(g.tw, g.ly) - 1, 4) AS d_ly_pct,
  TRUE AS higher_is_better,
  (SELECT FORMAT_DATE('%F', rwe) FROM r) AS week_end
FROM m
JOIN agg g ON g.k = m.k
LEFT JOIN bl ON bl.k = m.k
ORDER BY m.sort
