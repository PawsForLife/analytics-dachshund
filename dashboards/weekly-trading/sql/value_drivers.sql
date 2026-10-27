-- Dataset: value_drivers
-- Title: Customer value drivers
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Per-customer and per-order economics of this week's purchasing customers and their Food / AD / App penetration, with absolute change vs last week and the 12-week average. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
wk AS (
  SELECT w.week_start_date AS ws, w.week_end_date AS we, CAST(DATE_DIFF(c.we, w.week_end_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` w CROSS JOIN cal c
  WHERE w.week_end_date BETWEEN DATE_SUB(c.we, INTERVAL 84 DAY) AND c.we
),
ord AS (
  SELECT o.order_id, o.customer_id, w.k, o.order_created_date AS d, o.order_origin AS origin, o.is_auto_delivery_order AS ad, o.is_first_customer_order_complete AS fst,
    o.product_revenue_complete_excl_gst AS rev, o.product_margin_complete_excl_gst AS pm
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 90 DAY)
),
bk AS (
  SELECT order_id, LOGICAL_OR(is_food) AS food, SUM(quantity_complete) AS items, COUNT(DISTINCT IF(quantity_complete > 0, category_description, NULL)) AS ncat
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 90 DAY)
  GROUP BY 1
),
ob AS (
  SELECT o.*, IFNULL(b.food, FALSE) AS food, IFNULL(b.items, 0) AS items, IFNULL(b.ncat, 0) AS ncat
  FROM ord o LEFT JOIN bk b USING (order_id)
),
cwk AS (
  SELECT k, customer_id, LOGICAL_OR(food) AS f, LOGICAL_OR(ad) AS a, LOGICAL_OR(origin = 'Mobile App') AS p
  FROM ob GROUP BY 1, 2
),
w AS (
  SELECT o.k, o.orders, o.rev, o.pm, o.items, o.ncat, c.cust, c.fc, c.ac, c.pc
  FROM (SELECT k, COUNT(*) AS orders, SUM(rev) AS rev, SUM(pm) AS pm, SUM(items) AS items, SUM(ncat) AS ncat FROM ob GROUP BY k) o
  JOIN (SELECT k, COUNT(*) AS cust, COUNTIF(f) AS fc, COUNTIF(a) AS ac, COUNTIF(p) AS pc FROM cwk GROUP BY k) c USING (k)
),
m AS (
  SELECT w.k, x.metric, x.label, x.unit, x.sort, x.v
  FROM w, UNNEST([
    STRUCT('purchasing_customers' AS metric, 'Purchasing customers' AS label, 'n' AS unit, 1 AS sort, CAST(w.cust AS FLOAT64) AS v),
    STRUCT('orders_per_customer', 'Orders per customer', 'n', 2, w.orders / w.cust),
    STRUCT('revenue_per_customer', 'Revenue per customer', '$', 3, w.rev / w.cust),
    STRUCT('aov', 'AOV', '$', 4, w.rev / w.orders),
    STRUCT('pm_per_order', 'Product margin per order', '$', 5, w.pm / w.orders),
    STRUCT('items_per_order', 'Items per order', 'n', 6, w.items / w.orders),
    STRUCT('categories_per_order', 'Categories per order', 'n', 7, w.ncat / w.orders),
    STRUCT('buying_food_share', 'Buying food', 'pct', 8, 100 * w.fc / w.cust),
    STRUCT('on_ad_share', 'On Auto Delivery', 'pct', 9, 100 * w.ac / w.cust),
    STRUCT('app_share', 'Shopping on app', 'pct', 10, 100 * w.pc / w.cust)
  ]) x
),
a AS (
  SELECT metric, ANY_VALUE(label) AS label, ANY_VALUE(unit) AS unit, ANY_VALUE(sort) AS sort,
    MAX(IF(k = 0, v, NULL)) AS tw, MAX(IF(k = 1, v, NULL)) AS lw, AVG(IF(k BETWEEN 1 AND 12, v, NULL)) AS l13w
  FROM m GROUP BY metric
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, metric, label, unit, sort,
  ROUND(tw, IF(unit = 'n' AND sort = 1, 0, 4)) AS tw, ROUND(tw - lw, 4) AS d_lw, ROUND(tw - l13w, 4) AS d_l13w
FROM a ORDER BY sort
