-- Dataset: cx_contacts_weekly
-- Title: Weekly contacts trend
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Valid inbound customer contacts, closed orders, the governed Contact Rate per 1,000 closed orders, conversations and the share engaged by the Gladly AI assistant (Luna), week by week for the last 13 weeks; drives the worms on the contact tiles. Reads company__daily_cx_contact_rate, cx__conversation, reference__calendar_4_4_5_week.

WITH wk AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
conv AS (
  SELECT
    DIV(DATE_DIFF(wk.we, c.conversation_created_date, DAY), 7) AS k,
    IFNULL(c.is_engaged_by_gladly_ai, FALSE) AS ai,
    (SELECT COUNTIF(REGEXP_CONTAINS(LOWER(t.topic_name), 'bonnodog')) FROM UNNEST(c.conversation_topic_mapping) t) AS n_bd,
    (SELECT COUNTIF(NOT REGEXP_CONTAINS(LOWER(t.topic_name), 'bonnodog')) FROM UNNEST(c.conversation_topic_mapping) t) AS n_other
  FROM `petcircle-warehouse-cloud.business_layer.cx__conversation` c
  CROSS JOIN wk
  WHERE c.conversation_created_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
),
cv AS (
  SELECT k, COUNT(*) AS conversations, COUNTIF(ai) AS ai_n
  FROM conv WHERE n_other > 0 OR n_bd = 0
  GROUP BY k
),
cr AS (
  SELECT DIV(DATE_DIFF(wk.we, r.calendar_date, DAY), 7) AS k,
    SUM(r.count_of_valid_inbound_contacts_started) AS contacts, SUM(r.count_of_closed_order) AS closed_orders
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.company__daily_cx_contact_rate` r
  CROSS JOIN wk
  WHERE r.calendar_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
  GROUP BY 1
)
SELECT
  FORMAT_DATE('%Y-%m-%d', DATE_SUB(wk.we, INTERVAL 7 * cr.k DAY)) AS week_end,
  cr.k AS weeks_ago,
  cr.contacts,
  cr.closed_orders,
  ROUND(SAFE_DIVIDE(cr.contacts, cr.closed_orders) * 1000, 1) AS per_1k_orders,
  cv.conversations,
  ROUND(SAFE_DIVIDE(cv.ai_n, cv.conversations) * 100, 1) AS ai_engaged_pct
FROM cr
CROSS JOIN wk
LEFT JOIN cv ON cv.k = cr.k
WHERE cr.k BETWEEN 0 AND 12
ORDER BY week_end
