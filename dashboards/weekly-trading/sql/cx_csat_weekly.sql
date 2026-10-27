-- Dataset: cx_csat_weekly
-- Title: Weekly CSAT trend
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Weekly conversations, ratings and CSAT for Luna only, with a person and all, for the last 13 weeks, with Luna's share of conversations. Reads cx__conversation, cx__agent, reference__calendar_4_4_5_week.

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
  SELECT
    k,
    g AS handler_group,
    IF(handler != 'No agent', rating, NULL) AS r
  FROM b,
    UNNEST(CASE handler WHEN 'Luna only' THEN ['Luna only', 'All'] WHEN 'No agent' THEN ['All'] ELSE ['With a person', 'All'] END) AS g
),
a AS (
  SELECT k, handler_group, COUNT(*) AS conv, COUNT(r) AS rt, COUNTIF(r >= 4) AS hi
  FROM x
  GROUP BY k, handler_group
),
s AS (
  SELECT
    a.*,
    SUM(IF(handler_group = 'Luna only', conv, 0)) OVER (PARTITION BY k) AS luna_conv,
    SUM(IF(handler_group = 'All', conv, 0)) OVER (PARTITION BY k) AS all_conv
  FROM a
)
SELECT
  FORMAT_DATE('%Y-%m-%d', DATE_SUB((SELECT ws FROM wk), INTERVAL k * 7 DAY)) AS week_start,
  handler_group,
  conv AS conversations,
  IF(handler_group = 'All', ROUND(SAFE_DIVIDE(luna_conv, all_conv) * 100, 1), NULL) AS luna_only_share,
  rt AS ratings,
  ROUND(SAFE_DIVIDE(hi, rt) * 100, 1) AS csat_pct,
  (SELECT FORMAT_DATE('%Y-%m-%d', we) FROM wk) AS week_end
FROM s
ORDER BY k DESC, CASE handler_group WHEN 'Luna only' THEN 1 WHEN 'With a person' THEN 2 ELSE 3 END
