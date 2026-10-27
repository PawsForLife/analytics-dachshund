-- Dataset: new_by_category
-- Title: New customers by category
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Reach of new customers' first baskets across the six core category groups, counting a customer in every group their first basket touched, with change vs last week and the 12-week average. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
wk AS (
  SELECT w.week_start_date AS ws, w.week_end_date AS we, CAST(DATE_DIFF(c.we, w.week_end_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` w CROSS JOIN cal c
  WHERE w.week_end_date BETWEEN DATE_SUB(c.we, INTERVAL 84 DAY) AND c.we
),
fo AS (
  SELECT o.order_id, o.customer_id, w.k
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.is_first_customer_order_complete AND o.order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 90 DAY)
),
bl AS (
  SELECT DISTINCT order_id, category_group_description AS grp
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 90 DAY)
),
grp AS (
  SELECT * FROM UNNEST([
    STRUCT('Food and Treats' AS src, 'Food & Treats' AS category, 1 AS sort),
    STRUCT('Health and Wellness', 'Health & Wellness', 2),
    STRUCT('Litter', 'Litter', 3),
    STRUCT('Other Species', 'Other Species', 4),
    STRUCT('Accessories', 'Accessories', 5),
    STRUCT('Home and Living', 'Home & Living', 6)
  ])
),
hit AS (
  SELECT f.k, b.grp, COUNT(DISTINCT f.customer_id) AS n
  FROM fo f JOIN bl b USING (order_id) GROUP BY 1, 2
),
g AS (
  SELECT gp.category, gp.sort, kk.k, IFNULL(h.n, 0) AS n
  FROM grp gp CROSS JOIN (SELECT DISTINCT k FROM wk) kk LEFT JOIN hit h ON h.grp = gp.src AND h.k = kk.k
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, category, sort,
  SUM(IF(k = 0, n, 0)) AS new_tw,
  ROUND(SAFE_DIVIDE(SUM(IF(k = 0, n, 0)), SUM(IF(k = 1, n, 0))) - 1, 4) AS pct_lw,
  ROUND(SAFE_DIVIDE(SUM(IF(k = 0, n, 0)), AVG(IF(k BETWEEN 1 AND 12, n, NULL))) - 1, 4) AS pct_l13w
FROM g GROUP BY category, sort ORDER BY sort
