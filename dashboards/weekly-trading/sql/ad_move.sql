-- Dataset: ad_move
-- Title: AD live base movement
-- Tab: Auto Delivery
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Customer-level waterfall of the live Auto Delivery base (start + new AD new + new AD existing + reactivated - pauses - cancellations = end) for this week with LW, 4/12-week averages and LY. Reads product__auto_delivery_group__eod, product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH rep AS (SELECT week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week = TRUE),
lyr AS (SELECT week_end_date AS e FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_prior_year_latest_merch_complete_week = TRUE),
wk AS (
  SELECT DISTINCT CAST(DATE_DIFF(rep.e, c.week_end_date, DAY) / 7 AS INT64) AS k, c.week_end_date AS s1, DATE_SUB(c.week_end_date, INTERVAL 7 DAY) AS s0
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` c, rep
  WHERE c.week_end_date BETWEEN DATE_SUB(rep.e, INTERVAL 84 DAY) AND rep.e
  UNION ALL SELECT -1, lyr.e, DATE_SUB(lyr.e, INTERVAL 7 DAY) FROM lyr
),
g AS (
  SELECT valid_for_date AS d, customer_id, auto_delivery_group_state AS s
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__auto_delivery_group__eod` WHERE EXISTS (SELECT 1 FROM UNNEST(auto_delivery_order) ad_l WHERE ad_l.store_id = 'pc-au'))
  WHERE valid_for_date >= (SELECT MIN(s0) FROM wk) AND valid_for_date <= (SELECT e FROM rep)
    AND valid_for_date IN (SELECT s0 FROM wk UNION DISTINCT SELECT s1 FROM wk)
    AND auto_delivery_group_state IN ('Active','Paused')
),
cw AS (
  SELECT w.k, g.customer_id,
    LOGICAL_OR(g.d = w.s0 AND g.s = 'Active') AS st,
    LOGICAL_OR(g.d = w.s1 AND g.s = 'Active') AS en,
    LOGICAL_OR(g.d = w.s1 AND g.s = 'Paused') AS ep
  FROM g JOIN wk w ON g.d IN (w.s0, w.s1)
  GROUP BY 1, 2
),
base AS (
  SELECT k, COUNTIF(st) AS start_n, COUNTIF(en) AS end_n,
    COUNTIF(st AND NOT en AND ep) AS pauses, COUNTIF(st AND NOT en AND NOT ep) AS cancels
  FROM cw GROUP BY 1
),
nw AS (
  SELECT w.k,
    COUNT(DISTINCT IF(o.is_first_customer_order_complete, o.customer_id, NULL)) AS new_new,
    COUNT(DISTINCT IF(NOT IFNULL(o.is_first_customer_order_complete, FALSE), o.customer_id, NULL)) AS new_exist
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN DATE_ADD(w.s0, INTERVAL 1 DAY) AND w.s1
  WHERE o.status != 'Cancelled' AND o.auto_delivery_order_cohort_complete = 1
    AND o.order_created_date >= (SELECT MIN(s0) FROM wk)
  GROUP BY 1
),
wv AS (
  SELECT b.k, b.start_n, n.new_new, n.new_exist,
    b.end_n - b.start_n - n.new_new - n.new_exist + b.pauses + b.cancels AS react,
    b.pauses, b.cancels, b.end_n
  FROM base b JOIN nw n USING (k)
),
lng AS (
  SELECT k, m.sort, m.v FROM wv,
  UNNEST([STRUCT(1 AS sort, CAST(start_n AS FLOAT64) AS v), STRUCT(2, CAST(new_new AS FLOAT64)), STRUCT(3, CAST(new_exist AS FLOAT64)),
          STRUCT(4, CAST(react AS FLOAT64)), STRUCT(5, CAST(pauses AS FLOAT64)), STRUCT(6, CAST(cancels AS FLOAT64)), STRUCT(7, CAST(end_n AS FLOAT64))]) m
),
agg AS (
  SELECT sort,
    MAX(IF(k = 0, v, NULL)) AS tw, MAX(IF(k = 1, v, NULL)) AS lw,
    AVG(IF(k BETWEEN 1 AND 4, v, NULL)) AS avg4, AVG(IF(k BETWEEN 1 AND 12, v, NULL)) AS avg12,
    MAX(IF(k = -1, v, NULL)) AS ly
  FROM lng GROUP BY 1
),
lab AS (
  SELECT * FROM UNNEST([
    STRUCT(1 AS sort, 'Active customers - start of week' AS metric, 'Customers with at least one live Auto Delivery schedule at the prior Sunday' AS sub, '' AS sign, FALSE AS inverted),
    STRUCT(2, 'New AD - new customers', 'Customers whose first-ever order was an Auto Delivery order this week', '+', FALSE),
    STRUCT(3, 'New AD - existing customers', 'First-ever Auto Delivery order this week from a customer who had ordered before', '+', FALSE),
    STRUCT(4, 'Reactivated AD', 'Existing customers coming back to a live Auto Delivery schedule by resume or a new group, derived as the residual so the waterfall ties exactly', '+', FALSE),
    STRUCT(5, 'Pauses', 'Customers who paused every Auto Delivery group and so left the live base, counted at customer level', '-', TRUE),
    STRUCT(6, 'Cancellations', 'Customers who cancelled every Auto Delivery group and so left the live base, counted at customer level', '-', TRUE),
    STRUCT(7, 'Active customers - end of week', 'Customers with at least one live Auto Delivery schedule at this Sunday', '', FALSE)
  ])
)
SELECT l.sort, l.metric, l.sub,
  CAST(a.tw AS INT64) AS tw, CAST(a.lw AS INT64) AS lw, ROUND(a.avg4, 2) AS avg4, ROUND(a.avg12, 2) AS avg12, CAST(a.ly AS INT64) AS ly,
  ROUND(SAFE_DIVIDE(a.tw, a.lw) - 1, 4) AS d_lw, ROUND(SAFE_DIVIDE(a.tw, a.avg4) - 1, 4) AS d_avg4,
  ROUND(SAFE_DIVIDE(a.tw, a.avg12) - 1, 4) AS d_avg12, ROUND(SAFE_DIVIDE(a.tw, a.ly) - 1, 4) AS d_ly,
  l.inverted, l.sign, CAST((SELECT e FROM rep) AS STRING) AS week_end
FROM lab l JOIN agg a USING (sort)
ORDER BY l.sort
