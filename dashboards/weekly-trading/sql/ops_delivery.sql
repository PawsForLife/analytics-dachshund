-- Dataset: ops_delivery
-- Title: Delivery promise by warehouse
-- Tab: Operations
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Share of fulfilment orders delivered on or before the promised date and click-to-delivery days by fulfilment warehouse and week for 7 weeks, bucketed on the promise date, with National pooled. Reads logistics__customer_order_delivery, reference__calendar_4_4_5_week. Orders limited to Pet Circle (store_id = 'pc-au').

WITH wk AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
fo_rows AS (
  SELECT
    f.fulfilment_warehouse AS wh,
    DATE_TRUNC(f.fulfilment_order_delivery.delivery_promise_date, WEEK(MONDAY)) AS week_start,
    d.customer_order_delivery_address.is_metro AS is_metro,
    f.fulfilment_order_delivery.count_with_delivery_promise_date AS c_promise,
    f.fulfilment_order_delivery.count_delivered_on_or_before_delivery_promise_date AS c_ontime,
    f.fulfilment_order_delivery.count_not_yet_delivered_in_full AS c_undel,
    f.fulfilment_order_delivery.click_to_delivery_days AS ctd
  FROM `petcircle-warehouse-cloud.business_layer.logistics__customer_order_delivery` d
  CROSS JOIN UNNEST(d.fulfilment_order) f
  CROSS JOIN wk
  WHERE d.order_created_date >= DATE_SUB(wk.ws, INTERVAL 150 DAY)
    AND d.order_id IN (SELECT o.order_id FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` o WHERE o.store_id = 'pc-au' AND o.order_created_date >= DATE_SUB((SELECT ws FROM wk), INTERVAL 150 DAY))
    AND f.fulfilment_order_delivery.delivery_promise_date >= DATE_SUB(wk.ws, INTERVAL 42 DAY)
    AND f.fulfilment_order_delivery.delivery_promise_date <= wk.we
    AND f.fulfilment_warehouse IN ('NSW-WH Eastern Creek', 'QLD-WH Crestmead', 'VIC-WH Tarneit', 'WA-WH Bibra Lake')
),
pooled AS (
  SELECT wh, week_start, is_metro, c_promise, c_ontime, c_undel, ctd FROM fo_rows
  UNION ALL
  SELECT 'ALL', week_start, is_metro, c_promise, c_ontime, c_undel, ctd FROM fo_rows
),
agg AS (
  SELECT
    wh,
    week_start,
    SUM(c_promise) AS n_promise,
    SUM(c_ontime) AS n_ontime,
    SUM(IF(is_metro, c_ontime, 0)) AS m_ontime,
    SUM(IF(is_metro, c_promise, 0)) AS m_promise,
    SUM(c_undel) AS n_undel,
    APPROX_QUANTILES(ctd, 100) AS q
  FROM pooled
  GROUP BY wh, week_start
),
fin AS (
SELECT
  CASE a.wh WHEN 'NSW-WH Eastern Creek' THEN 'EC' WHEN 'QLD-WH Crestmead' THEN 'BNE' WHEN 'VIC-WH Tarneit' THEN 'MEL' WHEN 'WA-WH Bibra Lake' THEN 'PER' ELSE 'ALL' END AS fc,
  CASE a.wh WHEN 'NSW-WH Eastern Creek' THEN 'Eastern Creek' WHEN 'QLD-WH Crestmead' THEN 'Crestmead' WHEN 'VIC-WH Tarneit' THEN 'Tarneit' WHEN 'WA-WH Bibra Lake' THEN 'Bibra Lake' ELSE 'National' END AS fc_name,
  FORMAT_DATE('%Y-%m-%d', a.week_start) AS week_start,
  a.n_promise,
  a.n_ontime,
  ROUND(100 * SAFE_DIVIDE(a.n_ontime, a.n_promise), 1) AS promise_pct,
  ROUND(100 * SAFE_DIVIDE(a.m_ontime, a.m_promise), 1) AS metro_pct,
  ROUND(a.q[OFFSET(20)], 1) AS ctd_p20,
  ROUND(a.q[OFFSET(50)], 1) AS ctd_med,
  ROUND(a.q[OFFSET(80)], 1) AS ctd_p80,
  ROUND(100 * SAFE_DIVIDE(a.n_undel, a.n_promise), 2) AS pct_undelivered,
  ROUND(100 * SAFE_DIVIDE(a.n_undel, a.n_promise), 2) <= 2.0 AS mature,
  FORMAT_DATE('%Y-%m-%d', wk.we) AS week_end
FROM agg a
CROSS JOIN wk

)
SELECT fin.*, ROUND(fin.promise_pct - LAG(fin.promise_pct) OVER (PARTITION BY fin.fc ORDER BY fin.week_start), 1) AS promise_pct_vs_pw, ROUND(fin.metro_pct - LAG(fin.metro_pct) OVER (PARTITION BY fin.fc ORDER BY fin.week_start), 1) AS metro_pct_vs_pw, ROUND(fin.promise_pct - FIRST_VALUE(fin.promise_pct) OVER (PARTITION BY fin.fc ORDER BY fin.week_start), 1) AS promise_pct_vs_first
FROM fin
ORDER BY fin.week_start, fin.fc
