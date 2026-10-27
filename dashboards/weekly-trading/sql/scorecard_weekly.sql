-- Dataset: scorecard_weekly
-- Title: Scorecard 13-week series
-- Tab: Highlights
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Weekly commercial metrics for the reporting week and the 12 weeks before it, for sparklines and the 13-week mean. Reads product__customer_order, customer__customer_order_basket, inventory__product_variant_item_mapping, customer__customer_lifecycle_attributes__eod, customer__forecast_customer_by_day, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we, c.merch_cal_week_number_of_year AS wn
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.rwe, INTERVAL 84 DAY) AND r.rwe
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
b AS (
  SELECT w.we, SUM(f.daily_forecast_gross_product_revenue) AS bud_rev
  FROM `petcircle-warehouse-cloud.business_layer.customer__forecast_customer_by_day` f
  JOIN wk w ON f.calendar_date BETWEEN w.ws AND w.we
  GROUP BY w.we
)
SELECT
  FORMAT_DATE('%F', w.we) AS week_end,
  CONCAT('W', CAST(w.wn AS STRING)) AS wk_label,
  ROUND(om.rev, 2) AS product_revenue,
  ROUND(om.nrev, 2) AS net_revenue,
  ROUND(om.pm, 2) AS product_margin,
  ROUND(SAFE_DIVIDE(om.pm, om.rev) * 100, 4) AS product_margin_pct,
  om.orders,
  u.units,
  ROUND(SAFE_DIVIDE(om.rev, om.orders), 2) AS aov,
  ROUND(SAFE_DIVIDE(om.rev, u.units), 2) AS asp,
  ROUND(SAFE_DIVIDE(u.units, om.orders), 4) AS units_per_order,
  om.pc AS purchasing_customers,
  a.a92 AS a92_base,
  ROUND(b.bud_rev, 2) AS budget_revenue
FROM wk w
LEFT JOIN om USING (we)
LEFT JOIN u USING (we)
LEFT JOIN a USING (we)
LEFT JOIN b USING (we)
ORDER BY w.we
