-- Dataset: super_users
-- Title: Super users
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Customers who in the same week bought Food, on Auto Delivery and via the app, as a share of purchasing customers and of revenue, with value density and movement vs last week and the 12-week average. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

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
  SELECT k, customer_id, LOGICAL_OR(food) AND LOGICAL_OR(ad) AND LOGICAL_OR(origin = 'Mobile App') AS su, SUM(rev) AS rev
  FROM ob GROUP BY 1, 2
),
w AS (
  SELECT k, COUNT(*) AS cust, COUNTIF(su) AS sc, SUM(rev) AS rev, SUM(IF(su, rev, 0)) AS srev,
    100 * COUNTIF(su) / COUNT(*) AS sh_c, 100 * SUM(IF(su, rev, 0)) / SUM(rev) AS sh_r
  FROM cwk GROUP BY k
),
a AS (
  SELECT
    MAX(IF(k = 0, sc, NULL)) AS super_users, MAX(IF(k = 0, sh_c, NULL)) AS share_customers, MAX(IF(k = 0, sh_r, NULL)) AS share_revenue,
    MAX(IF(k = 0, srev / sc, NULL)) AS rev_per_super, MAX(IF(k = 0, rev / cust, NULL)) AS rev_per_customer,
    MAX(IF(k = 0, srev, NULL)) AS super_revenue,
    MAX(IF(k = 1, sh_c, NULL)) AS lw_c, AVG(IF(k BETWEEN 1 AND 12, sh_c, NULL)) AS l13_c, MAX(IF(k = 1, sh_r, NULL)) AS lw_r, AVG(IF(k BETWEEN 1 AND 12, sh_r, NULL)) AS l13_r
  FROM w
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end,
  super_users, ROUND(share_customers, 4) AS share_customers, ROUND(share_revenue, 4) AS share_revenue,
  ROUND(rev_per_super, 2) AS rev_per_super, ROUND(rev_per_customer, 2) AS rev_per_customer,
  ROUND(rev_per_super / rev_per_customer, 4) AS value_index, ROUND(super_revenue, 2) AS super_revenue,
  ROUND(share_customers - lw_c, 4) AS share_customers_pp_lw, ROUND(share_customers - l13_c, 4) AS share_customers_pp_l13w,
  ROUND(share_revenue - lw_r, 4) AS share_revenue_pp_lw, ROUND(share_revenue - l13_r, 4) AS share_revenue_pp_l13w
FROM a
