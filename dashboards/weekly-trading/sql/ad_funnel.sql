-- Dataset: ad_funnel
-- Title: AD order funnel
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: This week's AD orders split by the customer's AD order number (AD1 new to AD, AD2-3, AD4+) with revenue, AOV and share of AD orders. Reads product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH rep AS (SELECT week_start_date AS s, week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE),
o AS (
  SELECT
    CASE WHEN o.auto_delivery_order_cohort_complete = 1 THEN 'AD1 - new to AD'
         WHEN o.auto_delivery_order_cohort_complete IN (2, 3) THEN 'AD2-3'
         WHEN o.auto_delivery_order_cohort_complete >= 4 THEN 'AD4+'
         ELSE 'Unassigned' END AS stage,
    o.product_revenue_complete_excl_gst AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o, rep
  WHERE o.order_created_date BETWEEN rep.s AND rep.e AND o.status != 'Cancelled' AND o.is_auto_delivery_order
)
SELECT stage,
  CASE stage WHEN 'AD1 - new to AD' THEN 1 WHEN 'AD2-3' THEN 2 WHEN 'AD4+' THEN 3 ELSE 4 END AS sort,
  COUNT(*) AS orders,
  ROUND(SUM(rev), 2) AS revenue,
  ROUND(SAFE_DIVIDE(SUM(rev), COUNT(*)), 2) AS aov,
  ROUND(SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()) * 100, 4) AS share_of_ad_orders,
  CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM o GROUP BY stage ORDER BY sort
