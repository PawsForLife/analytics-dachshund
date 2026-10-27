-- Dataset: channel_trend
-- Title: Channel share trend
-- Tab: Commercial
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Weekly orders, order share and AOV by channel for the reporting week and the 12 weeks before it, with each channel's 13-week change. Reads product__customer_order, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT * FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (SELECT week_end_date AS rwe FROM cal WHERE is_latest_merch_complete_week = TRUE),
wk AS (
  SELECT c.week_start_date AS ws, c.week_end_date AS we
  FROM cal c CROSS JOIN r
  WHERE c.week_end_date BETWEEN DATE_SUB(r.rwe, INTERVAL 84 DAY) AND r.rwe
),
o AS (
  SELECT w.we, o.order_id,
    ANY_VALUE(CASE WHEN o.order_origin = 'Schedule' THEN 'AD Scheduled' ELSE o.order_origin END) AS channel,
    ANY_VALUE(o.product_revenue_complete_excl_gst) AS rev
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o
  JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled'
    AND o.order_created_date BETWEEN (SELECT MIN(ws) FROM wk) AND (SELECT MAX(we) FROM wk)
  GROUP BY w.we, o.order_id
),
ch AS (SELECT channel FROM UNNEST(['Website', 'Mobile App', 'AD Scheduled', 'CX']) AS channel),
g AS (
  SELECT we, channel, COUNT(*) AS orders, SUM(rev) AS rev FROM o GROUP BY we, channel
),
t AS (SELECT we, COUNT(*) AS orders FROM o GROUP BY we),
d AS (
  SELECT w.we, ch.channel, IFNULL(g.orders, 0) AS orders,
    SAFE_DIVIDE(IFNULL(g.orders, 0), t.orders) * 100 AS share,
    SAFE_DIVIDE(g.rev, NULLIF(g.orders, 0)) AS aov
  FROM wk w CROSS JOIN ch
  LEFT JOIN g ON g.we = w.we AND g.channel = ch.channel
  LEFT JOIN t ON t.we = w.we
),
e AS (
  SELECT d.*,
    LAST_VALUE(share) OVER x - FIRST_VALUE(share) OVER x AS dsh,
    LAST_VALUE(aov) OVER x - FIRST_VALUE(aov) OVER x AS daov
  FROM d
  WINDOW x AS (PARTITION BY channel ORDER BY we ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)
SELECT
  FORMAT_DATE('%F', we) AS week_end,
  CONCAT(CAST(EXTRACT(DAY FROM we) AS STRING), FORMAT_DATE(' %b', we)) AS wk_label,
  channel,
  orders,
  ROUND(share, 4) AS share,
  ROUND(aov, 2) AS aov,
  ROUND(dsh, 4) AS share_change_13w_pp,
  ROUND(daov, 2) AS aov_change_13w,
  (SELECT FORMAT_DATE('%F', rwe) FROM r) AS report_week_end
FROM e
ORDER BY CASE channel WHEN 'Website' THEN 1 WHEN 'Mobile App' THEN 2 WHEN 'AD Scheduled' THEN 3 ELSE 4 END, we
