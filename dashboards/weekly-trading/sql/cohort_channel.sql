-- Dataset: cohort_channel
-- Title: Cohort by channel AOV
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: This week's orders by customer cohort (New, Reactivated, Returning) and order origin, with AOV and order count in every cell plus channel and cohort totals. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

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
  SELECT order_id, ANY_VALUE(date_of_previous_order) AS prev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN DATE_SUB((SELECT ws FROM cal), INTERVAL 1 DAY) AND (SELECT we FROM cal)
  GROUP BY 1
),
os AS (
  SELECT o.order_id, o.rev, o.origin,
    CASE WHEN o.fst THEN 'New' WHEN b.prev IS NULL OR DATE_DIFF(o.d, b.prev, DAY) >= 92 THEN 'Reactivated' ELSE 'Returning' END AS cohort
  FROM ord o LEFT JOIN bk b USING (order_id)
),
g AS (
  SELECT cohort, origin AS channel,
    COUNT(*) AS orders, SUM(rev) AS rev
  FROM os GROUP BY ROLLUP (cohort, origin)
  UNION ALL
  SELECT 'Channel total', origin, COUNT(*), SUM(rev) FROM os GROUP BY origin
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, IFNULL(cohort, 'Channel total') AS cohort, IFNULL(channel, 'Cohort total') AS channel,
  ROUND(rev / orders, 2) AS aov, orders
FROM g
ORDER BY CASE cohort WHEN 'New' THEN 1 WHEN 'Reactivated' THEN 2 WHEN 'Returning' THEN 3 ELSE 4 END,
  CASE channel WHEN 'Website' THEN 1 WHEN 'Mobile App' THEN 2 WHEN 'Schedule' THEN 3 WHEN 'CX' THEN 4 WHEN 'Cohort total' THEN 9 ELSE 5 END
