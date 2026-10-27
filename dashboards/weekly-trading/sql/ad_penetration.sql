-- Dataset: ad_penetration
-- Title: AD penetration
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: AD share of this week's orders and revenue, AD share of the active-92 base, and new vs existing AD customers with a 13-week new-to-AD average. Reads product__customer_order, customer__customer_lifecycle_attributes__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH rep AS (SELECT week_start_date AS s, week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE),
wk AS (SELECT k, DATE_SUB(rep.e, INTERVAL 7 * k + 6 DAY) AS ws, DATE_SUB(rep.e, INTERVAL 7 * k DAY) AS we FROM rep, UNNEST(GENERATE_ARRAY(0, 13)) AS k),
o AS (
  SELECT w.k, o.customer_id, o.is_auto_delivery_order AS ad, o.auto_delivery_order_cohort_complete AS adc, o.product_revenue_complete_excl_gst AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.order_created_date >= (SELECT MIN(ws) FROM wk)
),
wv AS (
  SELECT k,
    COUNT(*) AS orders, COUNTIF(ad) AS ad_orders, SUM(rev) AS rev, SUM(IF(ad, rev, 0)) AS ad_rev,
    COUNTIF(ad AND adc = 1) AS ad1_orders,
    COUNT(DISTINCT IF(adc = 1, customer_id, NULL)) AS new_to_ad,
    COUNT(DISTINCT IF(ad AND (adc IS NULL OR adc > 1), customer_id, NULL)) AS existing_ad,
    COUNT(DISTINCT IF(ad, customer_id, NULL)) AS ad_customers
  FROM o GROUP BY 1
),
a92 AS (
  SELECT COUNT(DISTINCT IF(is_active_auto_delivery_92, customer_id, NULL)) AS ad92, COUNT(DISTINCT IF(is_active_92, customer_id, NULL)) AS a92
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date = (SELECT e FROM rep)
)
SELECT
  ROUND(SAFE_DIVIDE(t.ad_orders, t.orders) * 100, 4) AS ad_order_share,
  ROUND(SAFE_DIVIDE(t.ad_rev, t.rev) * 100, 4) AS ad_revenue_share,
  a92.ad92, a92.a92,
  ROUND(SAFE_DIVIDE(a92.ad92, a92.a92) * 100, 4) AS ad92_share,
  t.new_to_ad, t.existing_ad, t.ad_customers,
  ROUND(SAFE_DIVIDE(t.ad1_orders, t.ad_orders) * 100, 4) AS new_to_ad_share_of_ad_orders,
  ROUND((SELECT AVG(new_to_ad) FROM wv WHERE k BETWEEN 1 AND 13), 2) AS new_to_ad_avg13,
  CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM wv t CROSS JOIN a92
WHERE t.k = 0
