-- Dataset: a92_flow
-- Title: A92 base flow, 13 weeks
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Weekly movement of the 92-day active base over the last 13 weeks: opening, new, reactivated, lapsed, net change and closing, with the 13-week average net change. Reads customer__customer_lifecycle_attributes__eod, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
wk AS (
  SELECT w.week_start_date AS ws, w.week_end_date AS we, CONCAT(w.merch_cal_year_name, ' W', CAST(w.merch_cal_week_number_of_year AS STRING)) AS wk_label
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` w CROSS JOIN cal c
  WHERE w.week_end_date BETWEEN DATE_SUB(c.we, INTERVAL 84 DAY) AND c.we
),
sun AS (
  SELECT we AS s FROM wk UNION DISTINCT SELECT DATE_SUB(we, INTERVAL 7 DAY) FROM wk
),
snap AS (
  SELECT DISTINCT valid_for_date AS s, customer_id
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_lifecycle_attributes__eod` WHERE store_id = 'pc-au')
  WHERE valid_for_date IN (SELECT s FROM sun) AND is_active_92
),
mem AS (
  SELECT we, customer_id, MAX(t) AS t, MAX(p) AS p
  FROM (
    SELECT s AS we, customer_id, 1 AS t, 0 AS p FROM snap
    UNION ALL
    SELECT DATE_ADD(s, INTERVAL 7 DAY), customer_id, 0, 1 FROM snap
  )
  WHERE we IN (SELECT we FROM wk)
  GROUP BY 1, 2
),
nw AS (
  SELECT DISTINCT w.we, o.customer_id
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.is_first_customer_order_complete AND o.order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 90 DAY)
),
f AS (
  SELECT m.we,
    SUM(m.p) AS opening,
    COUNTIF(m.t = 1 AND m.p = 0 AND n.customer_id IS NOT NULL) AS new_customers,
    COUNTIF(m.t = 1 AND m.p = 0 AND n.customer_id IS NULL) AS reactivated,
    COUNTIF(m.t = 0 AND m.p = 1) AS lapsed,
    SUM(m.t) AS closing
  FROM mem m LEFT JOIN nw n ON n.we = m.we AND n.customer_id = m.customer_id
  GROUP BY 1
)
SELECT FORMAT_DATE('%Y-%m-%d', f.we) AS week_end, w.wk_label, f.opening, f.new_customers, f.reactivated, f.lapsed,
  f.closing - f.opening AS net_change, f.closing,
  ROUND(AVG(f.closing - f.opening) OVER (), 1) AS avg_net_13w
FROM f JOIN wk w USING (we)
ORDER BY f.we
