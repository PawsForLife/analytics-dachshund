-- Dataset: cx_csat_channel
-- Title: CSAT by channel
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: CSAT by first-contact channel, Luna only versus with a person, over the last 13 weeks. Reads cx__conversation, cx__agent, reference__calendar_4_4_5_week.

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
    cg AS channel,
    hg AS handler_group,
    rating AS r
  FROM b,
    UNNEST([ch, 'All channels']) AS cg,
    UNNEST(CASE handler WHEN 'Luna only' THEN ['Luna only', 'All rated'] WHEN 'No agent' THEN CAST([] AS ARRAY<STRING>) ELSE ['With a person', 'All rated'] END) AS hg
),
a AS (
  SELECT
    channel,
    handler_group,
    COUNT(*) AS conv13,
    COUNT(r) AS r13,
    COUNTIF(r >= 4) AS hi13,
    SUM(r) AS sum13
  FROM x
  GROUP BY channel, handler_group
)
SELECT
  channel,
  handler_group,
  conv13 AS conversations_13w,
  r13 AS ratings_13w,
  ROUND(SAFE_DIVIDE(hi13, r13) * 100, 1) AS csat_pct_13w,
  ROUND(SAFE_DIVIDE(sum13, r13), 2) AS csat_avg_13w,
  r13 < 30 AS suppressed_13w,
  CASE channel WHEN 'All channels' THEN 0 WHEN 'Chat' THEN 1 WHEN 'Email' THEN 2 WHEN 'Phone Call' THEN 3 WHEN 'SMS' THEN 4 WHEN 'WhatsApp' THEN 5 WHEN 'Unknown' THEN 7 ELSE 6 END * 10
    + CASE handler_group WHEN 'Luna only' THEN 1 WHEN 'With a person' THEN 2 ELSE 3 END AS sort,
  (SELECT FORMAT_DATE('%Y-%m-%d', we) FROM wk) AS week_end
FROM a
ORDER BY sort, channel
