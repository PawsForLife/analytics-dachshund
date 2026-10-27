-- Dataset: tenure
-- Title: A92 base by tenure
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: The 92-day active base at the reporting Sunday split by time since first order, with each bucket's share and Auto Delivery activity rate. Reads customer__customer_lifecycle_attributes__eod, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
c AS (
  SELECT customer_id, MAX(IFNULL(days_since_first_order, 0)) AS dsf, LOGICAL_OR(IFNULL(is_active_auto_delivery_92, FALSE)) AS ad
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date = (SELECT we FROM cal) AND is_active_92
  GROUP BY 1
),
b AS (
  SELECT CASE WHEN dsf < 180 THEN '<6m' WHEN dsf < 730 THEN '6-24m' ELSE '24m+' END AS bucket,
    CASE WHEN dsf < 180 THEN 1 WHEN dsf < 730 THEN 2 ELSE 3 END AS sort,
    COUNT(*) AS customers, COUNTIF(ad) AS ad_n
  FROM c GROUP BY 1, 2
  UNION ALL
  SELECT 'Total', 9, COUNT(*), COUNTIF(ad) FROM c
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, bucket, sort, customers,
  ROUND(100 * customers / (SELECT COUNT(*) FROM c), 4) AS share,
  ROUND(100 * ad_n / customers, 4) AS ad_pct
FROM b ORDER BY sort
