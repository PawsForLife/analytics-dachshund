-- Dataset: cx_csat_handler
-- Title: CSAT by handler
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: CSAT and response rate for conversations handled by Luna only, Luna then a person, or a person only, over the last 13 weeks and the reporting week. Reads cx__conversation, cx__agent, reference__calendar_4_4_5_week.

WITH wk AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
ag AS (
  SELECT agent_id, MAX(IF(agent_name = 'Gladly Sidekick', 1, 0)) AS is_luna
  FROM `petcircle-warehouse-cloud.business_layer.cx__agent`
  GROUP BY agent_id
),
b AS (
  SELECT
    DIV(DATE_DIFF(wk.we, c.conversation_created_date, DAY), 7) AS k,
    IFNULL(c.first_contact_channel_type, 'Unknown') AS ch,
    CASE
      WHEN c.current_agent_id IS NULL THEN 'No agent'
      WHEN ag.is_luna = 1 THEN 'Luna only'
      WHEN IFNULL(c.is_engaged_by_gladly_ai, FALSE) THEN 'Luna then a person'
      ELSE 'Person only'
    END AS handler,
    c.rating_score_of_current_agent AS rating
  FROM `petcircle-warehouse-cloud.business_layer.cx__conversation` c
  CROSS JOIN wk
  LEFT JOIN ag ON ag.agent_id = c.current_agent_id
  WHERE c.conversation_created_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
),
x AS (
  SELECT g, k, IF(handler != 'No agent' AND rating IS NOT NULL, rating, NULL) AS r
  FROM b, UNNEST([handler, 'All']) AS g
),
a AS (
  SELECT
    g,
    COUNT(*) AS conv13,
    COUNTIF(k = 0) AS conv_tw,
    COUNT(r) AS r13,
    COUNTIF(k = 0 AND r IS NOT NULL) AS r_tw,
    COUNTIF(r >= 4) AS hi13,
    COUNTIF(k = 0 AND r >= 4) AS hi_tw,
    SUM(r) AS sum13
  FROM x
  GROUP BY g
),
t AS (
  SELECT a.*, MAX(IF(g = 'All', conv13, NULL)) OVER () AS tot13, MAX(IF(g = 'All', conv_tw, NULL)) OVER () AS tot_tw
  FROM a
)
SELECT
  g AS handler,
  CASE g WHEN 'Luna only' THEN 1 WHEN 'Luna then a person' THEN 2 WHEN 'Person only' THEN 3 WHEN 'No agent' THEN 4 ELSE 5 END AS sort,
  conv13 AS conversations_13w,
  ROUND(SAFE_DIVIDE(conv13, tot13) * 100, 1) AS conv_share_13w,
  r13 AS ratings_13w,
  ROUND(SAFE_DIVIDE(r13, conv13) * 100, 1) AS response_rate_13w,
  ROUND(SAFE_DIVIDE(hi13, r13) * 100, 1) AS csat_pct_13w,
  ROUND(SAFE_DIVIDE(sum13, r13), 2) AS csat_avg_13w,
  conv_tw AS conversations_tw,
  ROUND(SAFE_DIVIDE(conv_tw, tot_tw) * 100, 1) AS conv_share_tw,
  r_tw AS ratings_tw,
  ROUND(SAFE_DIVIDE(hi_tw, r_tw) * 100, 1) AS csat_pct_tw,
  r13 < 30 AS suppressed_13w,
  r_tw < 30 AS suppressed_tw,
  (SELECT FORMAT_DATE('%Y-%m-%d', we) FROM wk) AS week_end
FROM t
ORDER BY sort
