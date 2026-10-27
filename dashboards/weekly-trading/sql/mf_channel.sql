-- Dataset: mf_channel
-- Title: Orders bridge by channel
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Sessions, conversion and orders by acquisition channel against last week and the prior-12-week average, with an orders bridge splitting the change into volume, rate and interaction effects. Reads online__session, reference__calendar_4_4_5_week.

WITH r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
wk AS (
  SELECT c.week_start_date, c.week_end_date, CAST(DATE_DIFF(r.ws, c.week_start_date, DAY) / 7 AS INT64) AS k
  FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week` c CROSS JOIN r
  WHERE c.week_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.ws
),
m AS (
  SELECT
    wk.k,
    j.acquisition_channel_group AS channel_group,
    CASE
      WHEN j.digital_platform_type = 'Mobile App' THEN 'Mobile App'
      WHEN j.acquisition_channel_group IN ('SEM', 'Social', 'SEO', 'Email', 'Direct', 'SMS') THEN j.acquisition_channel_group
      ELSE 'Other'
    END AS channel,
    IFNULL(j.digital_platform_type, '') != 'Mobile App'
      AND IFNULL(j.acquisition_channel_group, '(null)') NOT IN ('SEM', 'Social', 'SEO', 'Email', 'Direct', 'SMS', 'Other', 'Push', 'AI LLM') AS unplaced,
    j.session_count AS s,
    j.session_count_has_converted AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` j
  JOIN wk ON j.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE j.bot_likelihood_category = 'Likely Human' AND j.business_line = 'Pet Circle'
    AND j.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
),
nb AS (SELECT COUNT(DISTINCT k) AS n FROM m WHERE k BETWEEN 1 AND 12),
unp AS (
  SELECT STRING_AGG(DISTINCT IFNULL(channel_group, '(null)'), ', ' ORDER BY IFNULL(channel_group, '(null)')) AS v
  FROM m WHERE unplaced AND k = 0
),
c AS (
  SELECT channel,
    SUM(IF(k = 0, s, 0)) AS s_tw, SUM(IF(k = 0, o, 0)) AS o_tw,
    SUM(IF(k = 1, s, 0)) AS s_lw,
    SUM(IF(k BETWEEN 1 AND 12, s, 0)) / (SELECT n FROM nb) AS s_b,
    SUM(IF(k BETWEEN 1 AND 12, o, 0)) / (SELECT n FROM nb) AS o_b
  FROM m GROUP BY 1
),
br AS (
  SELECT c.*,
    SAFE_DIVIDE(o_tw, s_tw) AS cvr_tw, SAFE_DIVIDE(o_b, s_b) AS cvr_b,
    (s_tw - s_b) * SAFE_DIVIDE(o_b, s_b) AS vol,
    (SAFE_DIVIDE(o_tw, s_tw) - SAFE_DIVIDE(o_b, s_b)) * s_b AS rate,
    (s_tw - s_b) * (SAFE_DIVIDE(o_tw, s_tw) - SAFE_DIVIDE(o_b, s_b)) AS inter,
    o_tw - o_b AS d_orders
  FROM c
),
tot AS (
  SELECT 'Total' AS channel, SUM(s_tw) AS s_tw, SUM(o_tw) AS o_tw, SUM(s_lw) AS s_lw, SUM(s_b) AS s_b, SUM(o_b) AS o_b,
    SAFE_DIVIDE(SUM(o_tw), SUM(s_tw)) AS cvr_tw, SAFE_DIVIDE(SUM(o_b), SUM(s_b)) AS cvr_b,
    SUM(vol) AS vol, SUM(rate) AS rate, SUM(inter) AS inter, SUM(d_orders) AS d_orders
  FROM br
),
u AS (
  SELECT channel, s_tw, o_tw, s_lw, s_b, o_b, cvr_tw, cvr_b, vol, rate, inter, d_orders FROM br
  UNION ALL SELECT * FROM tot
),
chk AS (
  SELECT
    LOGICAL_AND(ABS(vol + rate + inter - d_orders) < 0.01) AS rows_ok,
    ABS((SELECT SUM(o_tw) - SUM(o_b) FROM br) - (SELECT d_orders FROM tot)) < 0.01
      AND ABS((SELECT SUM(o_tw) - SUM(o_b) FROM br) - (SELECT vol + rate + inter FROM tot)) < 0.01 AS total_ok
  FROM u
)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  u.channel,
  CASE u.channel WHEN 'SEM' THEN 1 WHEN 'Mobile App' THEN 2 WHEN 'Social' THEN 3 WHEN 'SEO' THEN 4
    WHEN 'Email' THEN 5 WHEN 'Direct' THEN 6 WHEN 'SMS' THEN 7 WHEN 'Other' THEN 8 ELSE 9 END AS sort,
  u.s_tw AS sessions,
  u.s_lw AS sessions_lw,
  ROUND(SAFE_DIVIDE(u.s_tw, u.s_lw) - 1, 4) AS sessions_vs_lw_pct,
  ROUND(u.s_b, 1) AS sessions_l12w,
  ROUND(SAFE_DIVIDE(u.s_tw, u.s_b) - 1, 4) AS sessions_vs_l12w_pct,
  ROUND(100 * SAFE_DIVIDE(u.s_tw, t.s_tw), 4) AS session_share,
  ROUND(100 * u.cvr_tw, 4) AS cvr,
  ROUND(100 * u.cvr_b, 4) AS cvr_l12w,
  ROUND(100 * (u.cvr_tw - u.cvr_b), 4) AS cvr_vs_l12w_pp,
  u.o_tw AS orders,
  ROUND(100 * SAFE_DIVIDE(u.o_tw, t.o_tw), 4) AS orders_share,
  ROUND(u.o_b, 2) AS orders_l12w,
  ROUND(SAFE_DIVIDE(u.o_tw, u.o_b) - 1, 4) AS orders_vs_l12w_pct,
  ROUND(u.d_orders, 2) AS d_orders,
  ROUND(u.vol, 2) AS vol_effect,
  ROUND(u.rate, 2) AS rate_effect,
  ROUND(u.inter, 2) AS interaction,
  chk.rows_ok AS bridge_rows_ok,
  chk.total_ok AS bridge_sums_to_total,
  nb.n AS l12w_weeks,
  IFNULL(unp.v, '') AS unplaced_channel_groups
FROM u CROSS JOIN tot t CROSS JOIN chk CROSS JOIN nb CROSS JOIN unp CROSS JOIN r
ORDER BY sort
