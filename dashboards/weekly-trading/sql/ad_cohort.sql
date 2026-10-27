-- Dataset: ad_cohort
-- Title: AD1 cohort progression
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: For each of the 19 calendar-month AD1 cohorts ending with the reporting month, the cohort size and the share that placed a 2nd AD order within 90 days and a 3rd and 4th AD order within 180 days of their first AD order. A cohort's rate shows only once its window has fully closed (last day of the cohort month plus 90 or 180 days); open windows are left blank, and the steady-state rates are the average of the closed cohorts. Reads product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH rep AS (SELECT week_end_date AS e, DATE_TRUNC(week_end_date, MONTH) AS m0 FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE),
o AS (
  SELECT o.customer_id, o.order_created_date AS d, o.auto_delivery_order_cohort_complete AS adc
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o, rep
  WHERE o.status != 'Cancelled' AND o.auto_delivery_order_cohort_complete BETWEEN 1 AND 4
    AND o.order_created_date >= DATE_SUB(rep.m0, INTERVAL 18 MONTH) AND o.order_created_date <= rep.e
),
c AS (
  SELECT customer_id, MIN(IF(adc = 1, d, NULL)) AS d1, MIN(IF(adc = 2, d, NULL)) AS d2, MIN(IF(adc = 3, d, NULL)) AS d3, MIN(IF(adc = 4, d, NULL)) AS d4
  FROM o GROUP BY 1
  HAVING MIN(IF(adc = 1, d, NULL)) IS NOT NULL
),
m AS (
  SELECT DATE_TRUNC(d1, MONTH) AS ms, COUNT(*) AS n,
    COUNTIF(d2 <= DATE_ADD(d1, INTERVAL 90 DAY)) AS a2,
    COUNTIF(d3 <= DATE_ADD(d1, INTERVAL 180 DAY)) AS a3,
    COUNTIF(d4 <= DATE_ADD(d1, INTERVAL 180 DAY)) AS a4
  FROM c GROUP BY 1
),
f AS (
  SELECT m.*, DATE_ADD(LAST_DAY(m.ms), INTERVAL 90 DAY) AS close90, DATE_ADD(LAST_DAY(m.ms), INTERVAL 180 DAY) AS close180,
    DATE_ADD(LAST_DAY(m.ms), INTERVAL 90 DAY) <= rep.e AS done90, DATE_ADD(LAST_DAY(m.ms), INTERVAL 180 DAY) <= rep.e AS done180
  FROM m, rep
),
r AS (
  SELECT f.*, IF(done90, 100 * a2 / n, NULL) AS r2, IF(done180, 100 * a3 / n, NULL) AS r3, IF(done180, 100 * a4 / n, NULL) AS r4 FROM f
),
s AS (SELECT AVG(r2) AS s2, AVG(r3) AS s3, AVG(r4) AS s4 FROM r)
SELECT
  ROW_NUMBER() OVER (ORDER BY r.ms) AS sort,
  FORMAT_DATE('%b %y', r.ms) AS month_label,
  CAST(r.ms AS STRING) AS month_start,
  r.n, ROUND(r.r2, 2) AS r2, ROUND(r.r3, 2) AS r3, ROUND(r.r4, 2) AS r4,
  r.done90 AS complete_90, r.done180 AS complete_180, r.done180 AS mature,
  CAST(r.close90 AS STRING) AS window_90_closes, CAST(r.close180 AS STRING) AS window_180_closes,
  ROUND(s.s2, 2) AS steady_r2, ROUND(s.s3, 2) AS steady_r3, ROUND(s.s4, 2) AS steady_r4,
  CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM r CROSS JOIN s
ORDER BY r.ms
