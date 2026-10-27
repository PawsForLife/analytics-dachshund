-- Dataset: mf_acq_channels
-- Title: Acquisition channel scorecard
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Sessions, orders, conversion, revenue, new customers and paid spend efficiency for every Pet Circle acquisition channel against the prior-12-week average. Reads online__session, product__customer_order, marketing__campaign_performance, marketing__campaign, marketing__ad_platform, reference__calendar_4_4_5_week. Campaigns for other businesses (Bonnodog, Pharmacy) are excluded from spend.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
w AS (
  SELECT DIV(DATE_DIFF(r.we, s.session_start_date, DAY), 7) AS k,
    s.acquisition_channel AS ch, MAX(s.acquisition_channel_group) AS grp,
    SUM(s.session_count) AS s, SUM(s.session_count_has_converted) AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s CROSS JOIN r
  WHERE s.session_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
    AND s.business_line = 'Pet Circle' AND s.bot_likelihood_category = 'Likely Human'
  GROUP BY 1, 2
),
nb AS (SELECT COUNT(DISTINCT k) AS n FROM w WHERE k BETWEEN 1 AND 12),
c AS (
  SELECT ch, MAX(grp) AS grp,
    SUM(IF(k = 0, s, 0)) AS s_tw, SUM(IF(k BETWEEN 1 AND 12, s, 0)) / (SELECT n FROM nb) AS s_b,
    SUM(IF(k = 0, o, 0)) AS o_tw, SUM(IF(k BETWEEN 1 AND 12, o, 0)) / (SELECT n FROM nb) AS o_b
  FROM w GROUP BY 1
),
ords AS (
  SELECT m.order_id,
    ARRAY_AGG(s.acquisition_channel ORDER BY s.session_start_datetime LIMIT 1)[OFFSET(0)] AS ch
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s CROSS JOIN r, UNNEST(s.session_order_mapping) AS m
  WHERE s.session_start_date BETWEEN r.ws AND r.we
    AND s.business_line = 'Pet Circle' AND s.bot_likelihood_category = 'Likely Human'
    AND s.session_count_has_converted = 1
  GROUP BY 1
),
oc AS (
  SELECT ords.ch, COUNT(*) AS n_ord, SUM(o.product_revenue_complete_excl_gst) AS rev,
    COUNTIF(o.is_first_customer_order_complete) AS newc
  FROM ords JOIN (SELECT * FROM `petcircle-warehouse-cloud.business_layer.product__customer_order` WHERE store_id = 'pc-au') o ON o.order_id = ords.order_id
  WHERE o.status != 'Cancelled'
  GROUP BY 1
),
sp0 AS (
  SELECT DIV(DATE_DIFF(r.we, f.campaign_date, DAY), 7) AS k,
    CASE
      WHEN p.ad_media_type = 'Paid Social' THEN 'Paid Social'
      WHEN p.ad_media_type = 'Paid Display' THEN 'Display'
      WHEN p.ad_platform IN ('Google Ads', 'Bing Ads') AND cm.campaign_type = 'Brand' THEN 'Branded Paid Search'
      WHEN p.ad_platform IN ('Google Ads', 'Bing Ads') THEN 'Generic Paid Search'
      ELSE 'Unplaced'
    END AS ch,
    f.campaign_spend_amount AS spend
  FROM `petcircle-warehouse-cloud.business_layer.marketing__campaign_performance` f CROSS JOIN r
  JOIN `petcircle-warehouse-cloud.business_layer.marketing__campaign` cm ON cm.campaign_unique_id = f.campaign_unique_id
  LEFT JOIN `petcircle-warehouse-cloud.business_layer.marketing__ad_platform` p ON p.ad_platform = cm.ad_platform
  WHERE f.campaign_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.we
    AND NOT REGEXP_CONTAINS(LOWER(cm.campaign_name), r'bonno|\|\s*pharmacy\s*\|')
),
sp AS (
  SELECT ch, SUM(IF(k = 0, spend, 0)) AS sp_tw, SUM(IF(k BETWEEN 1 AND 12, spend, 0)) / (SELECT n FROM nb) AS sp_b
  FROM sp0 GROUP BY 1
),
j AS (
  SELECT c.ch, c.grp, c.s_tw, c.s_b, c.o_tw, c.o_b, oc.n_ord, oc.rev, oc.newc,
    IF(c.ch IN (SELECT ch FROM sp WHERE ch != 'Unplaced'), sp.sp_tw, NULL) AS sp_tw,
    IF(c.ch IN (SELECT ch FROM sp WHERE ch != 'Unplaced'), sp.sp_b, NULL) AS sp_b
  FROM c LEFT JOIN oc ON oc.ch = c.ch LEFT JOIN sp ON sp.ch = c.ch
),
tot AS (
  SELECT 'Total' AS ch, 'All' AS grp, SUM(s_tw) AS s_tw, SUM(s_b) AS s_b, SUM(o_tw) AS o_tw, SUM(o_b) AS o_b,
    SUM(n_ord) AS n_ord, SUM(rev) AS rev, SUM(newc) AS newc,
    (SELECT SUM(sp_tw) FROM sp WHERE ch != 'Unplaced') AS sp_tw, (SELECT SUM(sp_b) FROM sp WHERE ch != 'Unplaced') AS sp_b
  FROM j
),
u AS (
  SELECT j.*, 0 AS is_total FROM j UNION ALL SELECT tot.*, 1 AS is_total FROM tot
)
SELECT FORMAT_DATE('%F', (SELECT we FROM r)) AS week_end,
  ch AS acquisition_channel, grp AS acquisition_channel_group,
  s_tw AS sessions, ROUND(s_b, 1) AS sessions_l12w, ROUND(SAFE_DIVIDE(s_tw, s_b) - 1, 4) AS sessions_vs_l12w_pct,
  o_tw AS orders, ROUND(o_b, 1) AS orders_l12w, ROUND(SAFE_DIVIDE(o_tw, o_b) - 1, 4) AS orders_vs_l12w_pct,
  ROUND(100 * SAFE_DIVIDE(o_tw, s_tw), 4) AS cvr, ROUND(100 * SAFE_DIVIDE(o_b, s_b), 4) AS cvr_l12w,
  ROUND(100 * (SAFE_DIVIDE(o_tw, s_tw) - SAFE_DIVIDE(o_b, s_b)), 4) AS cvr_vs_l12w_pp,
  n_ord AS orders_mapped, ROUND(rev, 2) AS revenue, newc AS new_customers,
  ROUND(sp_tw, 2) AS spend, ROUND(sp_b, 2) AS spend_l12w,
  ROUND(SAFE_DIVIDE(sp_tw, o_tw), 2) AS cost_per_order, ROUND(SAFE_DIVIDE(sp_b, o_b), 2) AS cost_per_order_l12w,
  ROUND(SAFE_DIVIDE(sp_tw, newc), 2) AS cost_per_new_customer,
  ROUND(IF(sp_tw > 0, SAFE_DIVIDE(rev, sp_tw), NULL), 4) AS roas,
  ROUND(SAFE_DIVIDE(rev, s_tw), 4) AS revenue_per_session,
  IF(is_total = 1, IFNULL((SELECT SUM(sp_tw) FROM sp WHERE ch = 'Unplaced'), 0), NULL) AS spend_unplaced,
  ROW_NUMBER() OVER (ORDER BY is_total, s_tw DESC) AS sort,
  (SELECT n FROM nb) AS l12w_weeks
FROM u
ORDER BY sort
