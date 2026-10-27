-- Dataset: inv_concentration
-- Title: Revenue concentration, 30 days
-- Tab: Inventory
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Variants sold in the last 30 days ranked by revenue and cut into SKU-count bands (top 20%, next 30%, next 30%, bottom 20%), with each band's revenue and share. Reads customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cw AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE
), s AS (
  SELECT product_variant_code, SUM(product_variant_revenue_complete_excl_gst) AS rev, SUM(quantity_complete) AS qty
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE order_created_date BETWEEN (SELECT DATE_SUB(we, INTERVAL 29 DAY) FROM cw) AND (SELECT we FROM cw)
  GROUP BY 1
), k AS (
  SELECT rev, ROW_NUMBER() OVER (ORDER BY rev DESC, product_variant_code) AS rn, COUNT(*) OVER () AS n
  FROM s WHERE qty > 0
), b AS (
  SELECT CASE WHEN rn <= 0.2 * n THEN 1 WHEN rn <= 0.5 * n THEN 2 WHEN rn <= 0.8 * n THEN 3 ELSE 4 END AS sort, rev FROM k
), a AS (
  SELECT sort, COUNT(*) AS skus, SUM(rev) AS revenue FROM b GROUP BY sort
)
SELECT
  CASE sort WHEN 1 THEN 'Top 20% of SKUs' WHEN 2 THEN '20-50% of SKUs' WHEN 3 THEN '50-80% of SKUs' ELSE 'Bottom 20% of SKUs' END AS band,
  sort,
  skus,
  ROUND(SAFE_DIVIDE(skus, SUM(skus) OVER ()), 4) AS pct_skus,
  ROUND(revenue, 2) AS revenue,
  ROUND(SAFE_DIVIDE(revenue, SUM(revenue) OVER ()), 4) AS pct_revenue,
  FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cw)) AS week_end
FROM a
ORDER BY sort
