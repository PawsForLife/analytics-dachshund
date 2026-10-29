-- Dataset: cx_csat_handler_weekly
-- Title: Weekly CSAT by handler
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Weekly conversations, post-conversation ratings and CSAT (share of ratings scoring 4 or 5) for Luna only, Luna then a person, Person only and all conversations, for the last 13 weeks; drives the worms on the CSAT tiles. Reads cx__conversation, cx__agent, reference__calendar_4_4_5_week.

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
)
SELECT
  FORMAT_DATE('%Y-%m-%d', DATE_SUB((SELECT we FROM wk), INTERVAL k * 7 DAY)) AS week_end,
  g AS handler,
  COUNT(*) AS conversations,
  COUNT(r) AS ratings,
  ROUND(SAFE_DIVIDE(COUNTIF(r >= 4), COUNT(r)) * 100, 1) AS csat_pct
FROM x
WHERE g != 'No agent' AND k BETWEEN 0 AND 12
GROUP BY k, g
ORDER BY handler, week_end
