-- Dataset: ad_lenses
-- Title: AD share on four lenses
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: AD share on the A92 base, weekly purchasing customers, orders and revenue, this week vs the 445 LY week, with the YoY change in bps. Reads customer__customer_lifecycle_attributes__eod, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH p AS (
  SELECT 'tw' AS pk, week_start_date AS s, week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
  UNION ALL
  SELECT 'ly', week_start_date, week_end_date FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE
),
a92 AS (
  SELECT p.pk,
    SAFE_DIVIDE(COUNT(DISTINCT IF(l.is_active_auto_delivery_92, l.customer_id, NULL)), COUNT(DISTINCT IF(l.is_active_92, l.customer_id, NULL))) * 100 AS v
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au') l
  JOIN p ON l.valid_for_date = p.e
  WHERE l.valid_for_date IN (SELECT e FROM p)
  GROUP BY 1
),
o AS (
  SELECT p.pk,
    SAFE_DIVIDE(COUNT(DISTINCT IF(o.is_auto_delivery_order, o.customer_id, NULL)), COUNT(DISTINCT o.customer_id)) * 100 AS cust,
    SAFE_DIVIDE(COUNTIF(o.is_auto_delivery_order), COUNT(*)) * 100 AS ord,
    SAFE_DIVIDE(SUM(IF(o.is_auto_delivery_order, o.product_revenue_complete_excl_gst, 0)), SUM(o.product_revenue_complete_excl_gst)) * 100 AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN p ON o.order_created_date BETWEEN p.s AND p.e
  WHERE o.status != 'Cancelled' AND o.order_created_date >= (SELECT MIN(s) FROM p)
  GROUP BY 1
),
l AS (
  SELECT 'A92 base' AS lens, 1 AS sort, pk, v FROM a92
  UNION ALL SELECT 'Weekly customers', 2, pk, cust FROM o
  UNION ALL SELECT 'Orders', 3, pk, ord FROM o
  UNION ALL SELECT 'Revenue', 4, pk, rev FROM o
)
SELECT lens, sort,
  ROUND(MAX(IF(pk = 'tw', v, NULL)), 4) AS tw,
  ROUND(MAX(IF(pk = 'ly', v, NULL)), 4) AS ly,
  ROUND((MAX(IF(pk = 'tw', v, NULL)) - MAX(IF(pk = 'ly', v, NULL))) * 100, 2) AS yoy_bps,
  CAST((SELECT e FROM p WHERE pk = 'tw') AS STRING) AS week_end
FROM l GROUP BY lens, sort ORDER BY sort
