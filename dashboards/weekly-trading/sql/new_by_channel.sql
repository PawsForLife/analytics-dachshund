-- Dataset: new_by_channel
-- Title: New customers by acquisition channel
-- Tab: Customer
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: New customers this week by the acquisition channel of the session that placed their first order (SEM, Organic Search, Direct, Social, Email & SMS, Affiliates, AI LLM, Other), with first orders that have no tracked session shown as Unattributed. Change vs last week and the prior-12-week average, and share movement. Reads product__customer_order, online__session, reference__calendar_4_4_5_week. Pet Circle only (store_id = 'pc-au').

WITH cal AS (
  SELECT week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` WHERE is_latest_merch_complete_week
),
wk AS (
  SELECT w.week_start_date AS ws, w.week_end_date AS we, CAST(DATE_DIFF(c.we, w.week_end_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` w CROSS JOIN cal c
  WHERE w.week_end_date BETWEEN DATE_SUB(c.we, INTERVAL 84 DAY) AND c.we
),
fo AS (
  SELECT o.order_id, o.customer_id, w.k
  FROM (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o JOIN wk w ON o.order_created_date BETWEEN w.ws AND w.we
  WHERE o.status != 'Cancelled' AND o.is_first_customer_order_complete AND o.order_created_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 90 DAY)
),
ses AS (
  SELECT m.order_id,
    ARRAY_AGG(s.acquisition_channel ORDER BY s.session_start_datetime LIMIT 1)[OFFSET(0)] AS ch,
    ARRAY_AGG(s.acquisition_channel_group ORDER BY s.session_start_datetime LIMIT 1)[OFFSET(0)] AS grp
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s, UNNEST(s.session_order_mapping) AS m
  WHERE s.session_start_date >= DATE_SUB((SELECT we FROM cal), INTERVAL 97 DAY) AND s.session_start_date <= (SELECT we FROM cal)
    AND s.business_line = 'Pet Circle' AND s.session_count_has_converted = 1
  GROUP BY 1
),
nw AS (
  SELECT f.k, f.customer_id,
    CASE
      WHEN s.order_id IS NULL THEN 'Unattributed'
      WHEN s.ch = 'Affiliates' THEN 'Affiliates'
      WHEN s.grp = 'SEM' THEN 'SEM'
      WHEN s.grp = 'SEO' THEN 'Organic Search'
      WHEN s.grp = 'Social' THEN 'Social'
      WHEN s.grp = 'Direct' THEN 'Direct'
      WHEN s.grp IN ('Email', 'SMS', 'Push') THEN 'Email & SMS'
      WHEN s.grp = 'AI LLM' THEN 'AI LLM'
      ELSE 'Other'
    END AS channel
  FROM fo f LEFT JOIN ses s USING (order_id)
),
ch AS (
  SELECT * FROM UNNEST([STRUCT('SEM' AS channel, 1 AS sort), STRUCT('Organic Search', 2), STRUCT('Direct', 3), STRUCT('Social', 4), STRUCT('Email & SMS', 5), STRUCT('Affiliates', 6), STRUCT('AI LLM', 7), STRUCT('Other', 8), STRUCT('Unattributed', 9)])
),
g AS (
  SELECT c.channel, c.sort, kk.k, COUNT(n.customer_id) AS n
  FROM ch c CROSS JOIN (SELECT DISTINCT k FROM wk) kk LEFT JOIN nw n ON n.channel = c.channel AND n.k = kk.k
  GROUP BY 1, 2, 3
  UNION ALL
  SELECT 'Total', 99, kk.k, COUNT(n.customer_id) FROM (SELECT DISTINCT k FROM wk) kk LEFT JOIN nw n ON n.k = kk.k GROUP BY 3
),
t AS (SELECT k, n AS tot FROM g WHERE channel = 'Total'),
a AS (
  SELECT g.channel, g.sort,
    SUM(IF(g.k = 0, g.n, 0)) AS tw, SUM(IF(g.k = 1, g.n, 0)) AS lw, AVG(IF(g.k BETWEEN 1 AND 12, g.n, NULL)) AS l13,
    SUM(IF(g.k = 0, g.n, 0)) / SUM(IF(g.k = 0, t.tot, 0)) AS sh_tw,
    SUM(IF(g.k = 1, g.n, 0)) / SUM(IF(g.k = 1, t.tot, 0)) AS sh_lw,
    SUM(IF(g.k BETWEEN 1 AND 12, g.n, 0)) / SUM(IF(g.k BETWEEN 1 AND 12, t.tot, 0)) AS sh_13
  FROM g JOIN t USING (k) GROUP BY 1, 2
)
SELECT FORMAT_DATE('%Y-%m-%d', (SELECT we FROM cal)) AS week_end, channel, sort, tw AS new_tw,
  ROUND(SAFE_DIVIDE(tw, lw) - 1, 4) AS pct_lw, ROUND(SAFE_DIVIDE(tw, l13) - 1, 4) AS pct_l13w,
  ROUND(100 * sh_tw, 4) AS share,
  IF(channel = 'Total', NULL, ROUND(100 * (sh_tw - sh_lw), 4)) AS share_pp_lw,
  IF(channel = 'Total', NULL, ROUND(100 * (sh_tw - sh_13), 4)) AS share_pp_l13w
FROM a ORDER BY sort
