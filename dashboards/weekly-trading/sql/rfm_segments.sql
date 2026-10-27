-- Dataset: rfm_segments
-- Title: RFM buckets and segments
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: The customer file at the prior Sunday by RFM segment and value bucket, with week-on-week and vs-LY change, trailing 12-month value and this week's buying, order and revenue share. Reads customer__customer_recency_frequency_monetary_segments__eod, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_start_date AS ws, week_end_date AS we, DATE_SUB(week_start_date, INTERVAL 1 DAY) AS ps FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
avail AS (
  SELECT DISTINCT valid_for_date AS d
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_recency_frequency_monetary_segments__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date BETWEEN DATE_SUB((SELECT ps FROM cal), INTERVAL 371 DAY) AND (SELECT ps FROM cal)
    AND EXTRACT(DAYOFWEEK FROM valid_for_date) = 1
),
lyd AS (
  SELECT IFNULL(
    (SELECT MAX(d) FROM avail WHERE d <= DATE_SUB((SELECT ps FROM cal), INTERVAL 364 DAY)),
    (SELECT MIN(d) FROM avail)) AS d
),
dates AS (
  SELECT (SELECT ps FROM cal) AS d, 'cur' AS t
  UNION ALL SELECT DATE_SUB((SELECT ps FROM cal), INTERVAL 7 DAY), 'pw'
  UNION ALL SELECT (SELECT d FROM lyd), 'ly'
),
seg AS (
  SELECT dt.t, r.customer_id, ANY_VALUE(r.rfm_segment) AS segment,
    ANY_VALUE(r.product_revenue_in_365_day_window) AS rev12, ANY_VALUE(r.count_of_orders_in_365_day_window) AS ord12
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_recency_frequency_monetary_segments__eod` WHERE store_id = 'pc-au') r
  JOIN dates dt ON dt.d = r.valid_for_date
  WHERE r.valid_for_date IN (SELECT d FROM dates)
  GROUP BY 1, 2
),
twk AS (
  SELECT customer_id, COUNT(*) AS orders, SUM(product_revenue_complete_excl_gst) AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au')
  WHERE status != 'Cancelled' AND order_created_date BETWEEN (SELECT ws FROM cal) AND (SELECT we FROM cal)
  GROUP BY 1
),
bmap AS (
  SELECT * FROM UNNEST([
    STRUCT('Super High Value' AS segment, 'High Value' AS bucket, 1 AS bsort),
    STRUCT('High Value - Rescue', 'High Value', 1), STRUCT('Quality', 'High Value', 1), STRUCT('Key Opportunity', 'High Value', 1),
    STRUCT('Nurture', 'Developing Base', 2), STRUCT('At Risk - High Frequency', 'Developing Base', 2),
    STRUCT('High Value - Lapsed', 'At Risk', 3), STRUCT('Must not Lose - High Frequency', 'At Risk', 3), STRUCT('Almost Dormant - High Frequency', 'At Risk', 3),
    STRUCT('Must not Lose - Low Frequency', 'Disengaged', 4), STRUCT('Almost Dormant - Low Frequency', 'Disengaged', 4), STRUCT('At Risk - Low Frequency', 'Disengaged', 4)
  ])
),
s AS (
  SELECT IFNULL(seg.segment, 'Unknown') AS segment,
    COUNTIF(seg.t = 'cur') AS customers,
    COUNTIF(seg.t = 'pw') AS pw,
    COUNTIF(seg.t = 'ly') AS lyc,
    SUM(IF(seg.t = 'cur', seg.rev12, 0)) AS rev12,
    SUM(IF(seg.t = 'cur', seg.ord12, 0)) AS ord12,
    COUNTIF(seg.t = 'cur' AND w.customer_id IS NOT NULL) AS bought,
    SUM(IF(seg.t = 'cur', IFNULL(w.orders, 0), 0)) AS orders,
    SUM(IF(seg.t = 'cur', IFNULL(w.rev, 0), 0)) AS rev
  FROM seg LEFT JOIN twk w ON w.customer_id = seg.customer_id AND seg.t = 'cur'
  GROUP BY 1
),
sb AS (
  SELECT s.*, IFNULL(m.bucket, 'Unmapped') AS bucket, IFNULL(m.bsort, 5) AS bsort FROM s LEFT JOIN bmap m USING (segment)
),
rows_ AS (
  SELECT 'segment' AS kind, bucket, segment, bsort, customers, pw, lyc, rev12, ord12, bought, orders, rev FROM sb
  UNION ALL
  SELECT 'bucket', bucket, CAST(NULL AS STRING), bsort, SUM(customers), SUM(pw), SUM(lyc), SUM(rev12), SUM(ord12), SUM(bought), SUM(orders), SUM(rev) FROM sb GROUP BY bucket, bsort
  UNION ALL
  SELECT 'total', 'Total', CAST(NULL AS STRING), 9, SUM(customers), SUM(pw), SUM(lyc), SUM(rev12), SUM(ord12), SUM(bought), SUM(orders), SUM(rev) FROM sb
),
tot AS (SELECT customers AS fc, orders AS fo, rev AS fr FROM rows_ WHERE kind = 'total')
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, kind, bucket, segment,
  ROW_NUMBER() OVER (ORDER BY bsort, IF(kind = 'bucket', 0, 1), customers DESC) AS sort,
  customers,
  ROUND(100 * customers / tot.fc, 4) AS share_of_file,
  customers - pw AS wow,
  customers - lyc AS vs_ly,
  ROUND(SAFE_DIVIDE(rev12, customers), 2) AS rev_per_cust_12m,
  ROUND(SAFE_DIVIDE(ord12, customers), 4) AS orders_per_cust_12m,
  bought AS bought_this_wk,
  ROUND(100 * SAFE_DIVIDE(bought, customers), 4) AS penetration,
  orders AS orders_this_wk,
  ROUND(100 * SAFE_DIVIDE(orders, tot.fo), 4) AS order_share,
  ROUND(100 * SAFE_DIVIDE(rev, tot.fr), 4) AS rev_share,
  ROUND(SAFE_DIVIDE(rev, orders), 2) AS aov,
  FORMAT_DATE('%Y-%m-%d', (SELECT ps FROM cal)) AS file_date,
  DATE_DIFF((SELECT ps FROM cal), (SELECT d FROM lyd), DAY) AS ly_basis_days
FROM rows_ CROSS JOIN tot
ORDER BY sort
