-- Dataset: ad_order_type
-- Title: AD order type mix
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: This week's orders by order type (Transactional, AD Scheduled, AD Reorder, AD Transactional) with movement vs LW and the 12-week average, share, revenue, AOV, margin and items per order. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

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
t AS (
  SELECT k, IF(order_type = 'Schedule', 'AD Scheduled', order_type) AS order_type, COUNT(*) AS orders, SUM(rev) AS rev, SUM(pm) AS pm, SUM(items) AS items
  FROM ob WHERE k BETWEEN 0 AND 12 GROUP BY 1, 2
),
a AS (
  SELECT order_type,
    MAX(IF(k = 0, orders, NULL)) AS orders, MAX(IF(k = 1, orders, NULL)) AS orders_lw, AVG(IF(k BETWEEN 1 AND 12, orders, NULL)) AS orders_l13w,
    MAX(IF(k = 0, rev, NULL)) AS rev, MAX(IF(k = 0, pm, NULL)) AS pm, MAX(IF(k = 0, items, NULL)) AS items
  FROM t GROUP BY 1
)
SELECT order_type,
  CASE order_type WHEN 'Transactional' THEN 1 WHEN 'AD Scheduled' THEN 2 WHEN 'AD Reorder' THEN 3 WHEN 'AD Transactional' THEN 4 ELSE 5 END AS sort,
  orders,
  ROUND(SAFE_DIVIDE(orders, orders_lw) - 1, 4) AS pct_lw,
  ROUND(SAFE_DIVIDE(orders, orders_l13w) - 1, 4) AS pct_l13w,
  ROUND(SAFE_DIVIDE(orders, SUM(orders) OVER ()) * 100, 4) AS share,
  ROUND(rev, 2) AS revenue,
  ROUND(SAFE_DIVIDE(rev, orders), 2) AS aov,
  ROUND(SAFE_DIVIDE(pm, rev) * 100, 4) AS margin_pct,
  ROUND(SAFE_DIVIDE(items, orders), 4) AS items_per_order,
  CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM a WHERE orders IS NOT NULL
ORDER BY sort
