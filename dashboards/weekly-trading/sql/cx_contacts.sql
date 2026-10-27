-- Dataset: cx_contacts
-- Title: Customer contacts
-- Tab: CX
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Valid inbound customer contacts (Gladly, excluding customers who abandon within 10 seconds) this week against last week and the 12-week average, and the governed Contact Rate per 1,000 closed orders; plus the share of conversations with a contact reason and the share engaged by the Gladly AI assistant. Reads company__daily_cx_contact_rate, cx__conversation, reference__calendar_4_4_5_week. Also returns closed_orders_ref_tw, an independent count of non-cancelled orders closed in the week from logistics__customer_order_delivery and product__customer_order (all stores, like the governed table), used by the refresh gate to check the closed-order denominator. Reads logistics__customer_order_delivery and product__customer_order for that check.

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
  SELECT topic_name, reason FROM mapped
),
conv_reason AS (
  SELECT DISTINCT c.conversation_id AS cid
  FROM `petcircle-warehouse-cloud.business_layer.cx__conversation` c
  CROSS JOIN wk
  CROSS JOIN UNNEST(c.conversation_topic_mapping) t
  JOIN grp g ON g.topic_name = t.topic_name
  WHERE c.conversation_created_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
    AND g.reason IS NOT NULL
),
cr AS (
  SELECT DIV(DATE_DIFF(wk.we, r.calendar_date, DAY), 7) AS k,
    SUM(r.count_of_valid_inbound_contacts_started) AS contacts, SUM(r.count_of_closed_order) AS closed_orders
  FROM `petcircle-warehouse-cloud.business_layer_aggregate.company__daily_cx_contact_rate` r
  CROSS JOIN wk
  WHERE r.calendar_date BETWEEN DATE_SUB(wk.we, INTERVAL 90 DAY) AND wk.we
  GROUP BY 1
),
ref AS (
  SELECT COUNT(DISTINCT dl.order_id) AS n
  FROM `petcircle-warehouse-cloud.business_layer.logistics__customer_order_delivery` dl
  JOIN `petcircle-warehouse-cloud.business_layer.product__customer_order` o ON o.order_id = dl.order_id
  WHERE dl.order_created_date >= DATE_SUB((SELECT ws FROM wk), INTERVAL 120 DAY)
    AND o.order_created_date >= DATE_SUB((SELECT ws FROM wk), INTERVAL 120 DAY)
    AND dl.order_closed_date BETWEEN (SELECT ws FROM wk) AND (SELECT we FROM wk)
    AND o.status != 'Cancelled'
),
cv AS (
  SELECT c.k, COUNT(*) AS conversations, COUNTIF(c.ai) AS ai_n,
    COUNT(DISTINCT IF(r.cid IS NOT NULL, c.cid, NULL)) AS with_reason
  FROM conv_ok c
  LEFT JOIN conv_reason r ON r.cid = c.cid
  GROUP BY c.k
),
j AS (
  SELECT cr.k, cr.contacts, cr.closed_orders, cv.conversations, cv.ai_n, cv.with_reason
  FROM cr LEFT JOIN cv ON cv.k = cr.k
  WHERE cr.k BETWEEN 0 AND 12
)
SELECT
  SUM(IF(k = 0, contacts, 0)) AS contacts_tw,
  SUM(IF(k = 1, contacts, 0)) AS contacts_lw,
  ROUND(SUM(IF(k BETWEEN 1 AND 12, contacts, 0)) / 12, 1) AS contacts_avg12,
  ROUND(SAFE_DIVIDE(SUM(IF(k = 0, contacts, 0)), SUM(IF(k BETWEEN 1 AND 12, contacts, 0)) / 12) - 1, 4) AS contacts_vs_avg12_pct,
  SUM(IF(k = 0, closed_orders, 0)) AS orders_tw,
  (SELECT n FROM ref) AS closed_orders_ref_tw,
  ROUND(SAFE_DIVIDE(SUM(IF(k = 0, contacts, 0)), SUM(IF(k = 0, closed_orders, 0))) * 1000, 1) AS per_1k_orders_tw,
  ROUND(SAFE_DIVIDE(SUM(IF(k BETWEEN 1 AND 12, contacts, 0)), SUM(IF(k BETWEEN 1 AND 12, closed_orders, 0))) * 1000, 1) AS per_1k_orders_avg12,
  ROUND((SAFE_DIVIDE(SUM(IF(k = 0, contacts, 0)), SUM(IF(k = 0, closed_orders, 0))) - SAFE_DIVIDE(SUM(IF(k BETWEEN 1 AND 12, contacts, 0)), SUM(IF(k BETWEEN 1 AND 12, closed_orders, 0)))) * 1000, 1) AS d_per_1k_vs_avg12,
  SUM(IF(k = 0, conversations, 0)) AS conversations_tw,
  ROUND(SAFE_DIVIDE(SUM(IF(k = 0, with_reason, 0)), SUM(IF(k = 0, conversations, 0))) * 100, 1) AS with_reason_pct,
  ROUND(SAFE_DIVIDE(SUM(IF(k = 0, ai_n, 0)), SUM(IF(k = 0, conversations, 0))) * 100, 1) AS ai_engaged_pct,
  (SELECT FORMAT_DATE('%Y-%m-%d', we) FROM wk) AS week_end
FROM j
