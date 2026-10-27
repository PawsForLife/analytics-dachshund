-- Dataset: food_vs_nonfood
-- Title: Food vs non-food orders
-- Tab: Commercial
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: This week's orders split by whether the basket holds at least one Food line, comparing AOV, items, categories, margin per order and order and revenue share. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
ord AS (
  SELECT o.order_id, o.customer_id, o.order_created_date AS d, o.order_origin AS origin, o.is_auto_delivery_order AS ad, o.is_first_customer_order_complete AS fst,
    o.product_revenue_complete_excl_gst AS rev, o.product_margin_complete_excl_gst AS pm
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  WHERE o.status != 'Cancelled' AND o.order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
),
bk AS (
  SELECT order_id, LOGICAL_OR(is_food) AS food, SUM(quantity_complete) AS items, COUNT(DISTINCT IF(quantity_complete > 0, category_description, NULL)) AS ncat
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
  GROUP BY 1
),
g AS (
  SELECT IFNULL(b.food, FALSE) AS food, COUNT(*) AS orders, SUM(o.rev) AS rev, SUM(o.pm) AS pm, SUM(IFNULL(b.items, 0)) AS items, SUM(IFNULL(b.ncat, 0)) AS ncat
  FROM ord o LEFT JOIN bk b USING (order_id) GROUP BY 1
),
p AS (
  SELECT
    MAX(IF(food, orders, NULL)) AS fo, MAX(IF(NOT food, orders, NULL)) AS nfo,
    MAX(IF(food, rev, NULL)) AS fr, MAX(IF(NOT food, rev, NULL)) AS nr,
    MAX(IF(food, pm, NULL)) AS fp, MAX(IF(NOT food, pm, NULL)) AS np,
    MAX(IF(food, items, NULL)) AS fi, MAX(IF(NOT food, items, NULL)) AS ni,
    MAX(IF(food, ncat, NULL)) AS fc, MAX(IF(NOT food, ncat, NULL)) AS nc
  FROM g
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, x.metric, x.label, x.unit, x.sort, ROUND(x.food, 4) AS food, ROUND(x.nonfood, 4) AS nonfood
FROM p, UNNEST([
  STRUCT('aov' AS metric, 'AOV' AS label, '$' AS unit, 1 AS sort, fr / fo AS food, nr / nfo AS nonfood),
  STRUCT('items_per_order', 'Items per order', 'n', 2, fi / fo, ni / nfo),
  STRUCT('categories_per_order', 'Categories per order', 'n', 3, fc / fo, nc / nfo),
  STRUCT('pm_per_order', 'Product margin per order', '$', 4, fp / fo, np / nfo),
  STRUCT('order_share', 'Share of orders', 'pct', 5, 100 * fo / (fo + nfo), 100 * nfo / (fo + nfo)),
  STRUCT('revenue_share', 'Revenue share', 'pct', 6, 100 * fr / (fr + nr), 100 * nr / (fr + nr))
]) x
ORDER BY x.sort
