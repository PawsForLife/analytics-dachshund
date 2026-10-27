-- Dataset: ad_brands
-- Title: Top AD brands
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Top 8 brands by this week's AD revenue (basket product-variant revenue excl GST on AD orders) with movement vs LW and the 12-week average, AD orders containing the brand, AD AOV and share of the top-8 total. Reads customer__customer_order_basket, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH rep AS (SELECT week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE),
wk AS (SELECT k, DATE_SUB(rep.e, INTERVAL 7 * k + 6 DAY) AS ws, DATE_SUB(rep.e, INTERVAL 7 * k DAY) AS we FROM rep, UNNEST(GENERATE_ARRAY(0, 12)) AS k),
ord AS (
  SELECT o.order_id FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  WHERE o.status != 'Cancelled' AND o.is_auto_delivery_order AND o.order_created_date >= (SELECT MIN(ws) FROM wk) AND o.order_created_date <= (SELECT e FROM rep)
),
bw AS (
  SELECT w.k, b.brand, SUM(b.product_variant_revenue_complete_excl_gst) AS rev, COUNT(DISTINCT b.order_id) AS orders
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au') b
  JOIN wk w ON b.order_created_date BETWEEN w.ws AND w.we
  JOIN ord USING (order_id)
  WHERE b.order_created_date >= (SELECT MIN(ws) FROM wk) AND b.order_created_date <= (SELECT e FROM rep)
  GROUP BY 1, 2
),
a AS (
  SELECT brand,
    MAX(IF(k = 0, rev, NULL)) AS rev, MAX(IF(k = 1, rev, NULL)) AS rev_lw, SUM(IF(k BETWEEN 1 AND 12, rev, 0)) / 12 AS rev_l13w,
    MAX(IF(k = 0, orders, NULL)) AS orders, MAX(IF(k = 1, orders, NULL)) AS orders_lw, SUM(IF(k BETWEEN 1 AND 12, orders, 0)) / 12 AS orders_l13w
  FROM bw GROUP BY 1
),
top8 AS (SELECT *, ROW_NUMBER() OVER (ORDER BY rev DESC) AS rn FROM a WHERE rev IS NOT NULL AND brand IS NOT NULL)
SELECT brand, rn AS sort,
  ROUND(rev, 2) AS ad_revenue,
  ROUND(SAFE_DIVIDE(rev, rev_lw) - 1, 4) AS rev_pct_lw,
  ROUND(SAFE_DIVIDE(rev, rev_l13w) - 1, 4) AS rev_pct_l13w,
  orders AS ad_orders,
  ROUND(SAFE_DIVIDE(orders, orders_lw) - 1, 4) AS ord_pct_lw,
  ROUND(SAFE_DIVIDE(orders, orders_l13w) - 1, 4) AS ord_pct_l13w,
  ROUND(SAFE_DIVIDE(rev, orders), 2) AS ad_aov,
  ROUND(SAFE_DIVIDE(rev, SUM(rev) OVER ()) * 100, 4) AS share_of_top8,
  CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM top8 WHERE rn <= 8 ORDER BY rn
