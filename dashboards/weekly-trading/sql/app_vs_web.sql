-- Dataset: app_vs_web
-- Title: App vs website orders
-- Tab: Commercial
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: This week's Mobile App orders against Website orders on AOV, items, categories, AD share and share of all orders. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

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
  SELECT order_id, SUM(quantity_complete) AS items, COUNT(DISTINCT IF(quantity_complete > 0, category_description, NULL)) AS ncat
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
  GROUP BY 1
),
p AS (
  SELECT
    COUNT(*) AS t_o,
    COUNTIF(o.origin = 'Mobile App') AS a_o, COUNTIF(o.origin = 'Website') AS w_o,
    SUM(IF(o.origin = 'Mobile App', o.rev, 0)) AS a_r, SUM(IF(o.origin = 'Website', o.rev, 0)) AS w_r,
    SUM(IF(o.origin = 'Mobile App', IFNULL(b.items, 0), 0)) AS a_i, SUM(IF(o.origin = 'Website', IFNULL(b.items, 0), 0)) AS w_i,
    SUM(IF(o.origin = 'Mobile App', IFNULL(b.ncat, 0), 0)) AS a_c, SUM(IF(o.origin = 'Website', IFNULL(b.ncat, 0), 0)) AS w_c,
    COUNTIF(o.origin = 'Mobile App' AND o.ad) AS a_ad, COUNTIF(o.origin = 'Website' AND o.ad) AS w_ad
  FROM ord o LEFT JOIN bk b USING (order_id)
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, x.metric, x.label, x.unit, x.sort, ROUND(x.app, 4) AS app, ROUND(x.web, 4) AS web
FROM p, UNNEST([
  STRUCT('aov' AS metric, 'AOV' AS label, '$' AS unit, 1 AS sort, a_r / a_o AS app, w_r / w_o AS web),
  STRUCT('items_per_order', 'Items per order', 'n', 2, a_i / a_o, w_i / w_o),
  STRUCT('categories_per_order', 'Categories per order', 'n', 3, a_c / a_o, w_c / w_o),
  STRUCT('on_ad_share', 'On Auto Delivery', 'pct', 4, 100 * a_ad / a_o, 100 * w_ad / w_o),
  STRUCT('order_share', 'Order share of all orders', 'pct', 5, 100 * a_o / t_o, 100 * w_o / t_o)
]) x
ORDER BY x.sort
