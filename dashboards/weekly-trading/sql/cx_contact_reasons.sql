-- Dataset: cx_contact_reasons
-- Title: Contacts by reason
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Contacts by contact reason (agent-tagged Gladly topics rolled up to about 20 reasons by a fixed mapping, process tags excluded) this week against last week and the 12-week average, share of contacts and per 1,000 closed orders. Reads cx__conversation, company__daily_cx_contact_rate, reference__calendar_4_4_5_week.

WITH wk AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
conv AS (
  SELECT
    c.conversation_id AS cid,
    DIV(DATE_DIFF(wk.we, c.conversation_created_date, DAY), 7) AS k,
    IFNULL(c.is_engaged_by_gladly_ai, FALSE) AS ai,
    (SELECT COUNTIF(REGEXP_CONTAINS(LOWER(t.topic_name), 'bonnodog')) FROM UNNEST(c.conversation_topic_mapping) t) AS n_bd,
    (SELECT COUNTIF(NOT REGEXP_CONTAINS(LOWER(t.topic_name), 'bonnodog')) FROM UNNEST(c.conversation_topic_mapping) t) AS n_other
  FROM `petcircle-warehouse-cloud.business_layer.cx__conversation` c
  CROSS JOIN wk
  WHERE c.conversation_created_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
),
conv_ok AS (
  SELECT cid, k, ai FROM conv WHERE n_other > 0 OR n_bd = 0
),
topics AS (
  SELECT DISTINCT t.topic_name AS topic_name
  FROM `petcircle-warehouse-cloud.business_layer.cx__conversation` c
  CROSS JOIN wk
  CROSS JOIN UNNEST(c.conversation_topic_mapping) t
  WHERE c.conversation_created_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
    AND NOT REGEXP_CONTAINS(LOWER(t.topic_name), 'bonnodog')
),
mapped AS (
  SELECT
    topic_name,
    CASE
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|D\|Failed Delivery|Escalate \| CX Support - Failed Delivery') THEN 'Failed delivery'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|D\|Lost|Marked Delivered|FR\|D\|RTS') THEN 'Lost or not received'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|D\|Delayed|FR\|D\|Track within ETA|CXS \| Courier Outbound|FR\|W\|Packing Delay') THEN 'Delayed or tracking'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|D\|Wrong Address|FR\|D\|Redirection') THEN 'Wrong address or redirection'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|D\|Partial Delivery') THEN 'Partial delivery'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|D\|Delivery Feedback|FR\|D\|ATL Issues') THEN 'Delivery feedback'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|W\|Damaged') THEN 'Damaged in transit'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|W\|Missing Items|FR\|W\|Wrong Item') THEN 'Missing or wrong items'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|R\|Faulty|FR\|R\|Expiry|FR\|R\|Palatability|SK \| Return \| Faulty|SK \| Return \| Palatability') THEN 'Faulty, expiry or palatability'
      WHEN REGEXP_CONTAINS(topic_name, r'FR\|R\|COM|FR\|R\|Rainbow Bridge|SK \| Return|Escalate \| Returns') THEN 'Returns'
      WHEN REGEXP_CONTAINS(topic_name, r'^ACL - |CXS \| Credit Fail') THEN 'Refunds, credits and replacements'
      WHEN REGEXP_CONTAINS(topic_name, r'OP\|NO\|Price Beat|SK \| Best Price Guarantee|AE\|M\|Product or Pricing Error') THEN 'Price beat'
      WHEN REGEXP_CONTAINS(topic_name, r'OP\|NO\|') THEN 'Place order or payment'
      WHEN REGEXP_CONTAINS(topic_name, r'OP\|EO\||Cancel Order Priority Boost|Escalate \| Processing') THEN 'Change or cancel order'
      WHEN REGEXP_CONTAINS(topic_name, r'CXS \| Aged Orders|AE\|AD\|Discontinued') THEN 'Out of stock or aged order'
      WHEN REGEXP_CONTAINS(topic_name, r'AE\|AD\|Cancel AD') THEN 'Cancel Auto Delivery'
      WHEN REGEXP_CONTAINS(topic_name, r'AE\|AD\|') THEN 'Change Auto Delivery'
      WHEN REGEXP_CONTAINS(topic_name, r'AE\|AA\||AE\|GE\|Tech Support|AE\|GE\|Mobile App') THEN 'Account, login and app'
      WHEN REGEXP_CONTAINS(topic_name, r'^PCP|Prescription|^Vet\||AE\|GE\|Pharmacy|Escalate \| Vets|Escalate \| PC Pharmacy') THEN 'Pharmacy and vet'
      WHEN REGEXP_CONTAINS(topic_name, r'AE\|M\|Voucher|AE\|M\|Unsubscribe') THEN 'Vouchers and promotions'
      WHEN REGEXP_CONTAINS(topic_name, r'AE\|PS\||AE\|GE\|About Us|AE\|GE\|Contact Request|AE\|GE\|Chilled|AE\|GE\|Insurance|Request \| Call-back') THEN 'Pet advice and general enquiries'
      ELSE NULL
    END AS reason
  FROM topics
),
grp AS (
  SELECT
    topic_name,
    reason,
    CASE
      WHEN reason IN ('Failed delivery', 'Lost or not received', 'Delayed or tracking', 'Wrong address or redirection', 'Partial delivery', 'Delivery feedback') THEN 'Delivery'
      WHEN reason IN ('Damaged in transit', 'Missing or wrong items') THEN 'Warehouse'
      WHEN reason IN ('Faulty, expiry or palatability', 'Returns', 'Refunds, credits and replacements') THEN 'Product and returns'
      WHEN reason IN ('Price beat', 'Place order or payment', 'Change or cancel order', 'Out of stock or aged order') THEN 'Orders'
      WHEN reason IN ('Cancel Auto Delivery', 'Change Auto Delivery') THEN 'Auto Delivery'
      WHEN reason = 'Account, login and app' THEN 'Account'
      WHEN reason = 'Pharmacy and vet' THEN 'Pharmacy'
      WHEN reason = 'Vouchers and promotions' THEN 'Marketing'
      WHEN reason = 'Pet advice and general enquiries' THEN 'General'
    END AS reason_group
  FROM mapped
),
conv_reason AS (
  SELECT DISTINCT c.conversation_id AS cid, DIV(DATE_DIFF(wk.we, c.conversation_created_date, DAY), 7) AS k, g.reason, g.reason_group
  FROM `petcircle-warehouse-cloud.business_layer.cx__conversation` c
  CROSS JOIN wk
  CROSS JOIN UNNEST(c.conversation_topic_mapping) t
  JOIN grp g ON g.topic_name = t.topic_name
  WHERE c.conversation_created_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
    AND g.reason IS NOT NULL
),
orders AS (
  SELECT DIV(DATE_DIFF(wk.we, r.calendar_date, DAY), 7) AS k, SUM(r.count_of_closed_order) AS n_orders
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.company__daily_cx_contact_rate` r
  CROSS JOIN wk
  WHERE r.calendar_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
  GROUP BY 1
)
,
tot AS (
  SELECT
    SUM(IF(k = 0, 1, 0)) AS contacts_tw
  FROM conv_ok
),
rw AS (
  SELECT cr.reason, cr.reason_group,
    COUNT(DISTINCT IF(cr.k = 0, cr.cid, NULL)) AS tw,
    COUNT(DISTINCT IF(cr.k = 1, cr.cid, NULL)) AS lw,
    COUNT(DISTINCT IF(cr.k BETWEEN 1 AND 12, cr.cid, NULL)) / 12 AS avg12
  FROM conv_reason cr
  JOIN conv_ok ok ON ok.cid = cr.cid
  GROUP BY 1, 2
),
fin AS (
  SELECT rw.*, tot.contacts_tw, (SELECT n_orders FROM orders WHERE k = 0) AS orders_tw FROM rw CROSS JOIN tot
)
SELECT
  reason,
  reason_group,
  ROW_NUMBER() OVER (ORDER BY reason_group, tw DESC, reason) AS sort,
  tw,
  lw,
  ROUND(avg12, 1) AS avg12,
  ROUND(tw - avg12, 1) AS d_avg12,
  ROUND(SAFE_DIVIDE(tw, avg12) - 1, 4) AS pct_vs_avg12,
  ROUND(SAFE_DIVIDE(tw, contacts_tw) * 100, 1) AS share_tw,
  ROUND(SAFE_DIVIDE(tw, orders_tw) * 1000, 1) AS per_1k_orders_tw,
  (SELECT FORMAT_DATE('%Y-%m-%d', we) FROM wk) AS week_end
FROM fin
ORDER BY sort
