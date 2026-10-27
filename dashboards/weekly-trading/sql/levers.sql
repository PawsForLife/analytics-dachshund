-- Dataset: levers
-- Title: Strategic levers
-- Tab: Highlights
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Auto Delivery and Food penetration of all reporting-week orders, and App penetration of transactional orders (all orders minus AD Scheduled), against the 4-week and 12-week prior averages. Reads product__customer_order, customer__customer_order_basket, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we,
    c.week_end_date = r.rwe AS is_tw,
    c.week_end_date < r.rwe AND c.week_end_date >= DATE_SUB(r.rwe, INTERVAL 28 DAY) AS is_p4,
    c.week_end_date < r.rwe AS is_p12
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.rwe, INTERVAL 84 DAY) AND r.rwe
),
o AS (
  SELECT w.we, o.order_id,
    LOGICAL_OR(o.is_auto_delivery_order) AS is_ad,
    LOGICAL_OR(o.order_origin = 'Mobile App') AS is_app,
    LOGICAL_OR(o.order_type = 'AD Scheduled') AS is_sched
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
  GROUP BY w.we, o.order_id
),
fd AS (
  SELECT DISTINCT order_id
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.customer__customer_order_basket` WHERE store_id = 'pc-au')
  WHERE is_food AND order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
),
g AS (
  SELECT o.we, COUNT(*) AS den, COUNTIF(NOT o.is_sched) AS den_txn,
    COUNTIF(o.is_ad) AS n_ad, COUNTIF(fd.order_id IS NOT NULL) AS n_food,
    COUNTIF(o.is_app AND NOT o.is_sched) AS n_app
  FROM o LEFT JOIN fd USING (order_id)
  GROUP BY o.we
),
lg AS (
  SELECT w.is_tw, w.is_p4, w.is_p12, x.lever, x.sort, x.num, x.den, x.den_label, SAFE_DIVIDE(x.num, x.den) * 100 AS rate
  FROM wk w JOIN g USING (we),
  UNNEST([STRUCT('Auto Delivery %' AS lever, 1 AS sort, g.n_ad AS num, g.den AS den, 'orders' AS den_label),
          STRUCT('Food %', 2, g.n_food, g.den, 'orders'),
          STRUCT('App penetration %', 3, g.n_app, g.den_txn, 'transactional orders (excl. AD scheduled)')]) x
),
ag AS (
  SELECT lever, sort, ANY_VALUE(den_label) AS den_label,
    MAX(IF(is_tw, rate, NULL)) AS tw, MAX(IF(is_tw, num, NULL)) AS num, MAX(IF(is_tw, den, NULL)) AS den,
    AVG(IF(is_p4, rate, NULL)) AS avg4, AVG(IF(is_p12, rate, NULL)) AS avg12
  FROM lg GROUP BY lever, sort
)
SELECT lever, sort, ROUND(tw, 4) AS tw, num, den, den_label,
  ROUND(avg4, 4) AS avg4, ROUND(avg12, 4) AS avg12,
  ROUND((tw - avg4) * 100, 1) AS d_avg4_bps, ROUND((tw - avg12) * 100, 1) AS d_avg12_bps,
  (SELECT FORMAT_DATE('%F', rwe) FROM r) AS week_end
FROM ag
ORDER BY sort
