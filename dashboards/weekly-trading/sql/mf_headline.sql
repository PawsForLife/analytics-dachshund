-- Dataset: mf_headline
-- Title: Sessions, CVR and orders
-- Tab: Media & Funnel
-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly
-- Project: petcircle-data-ca
-- Labels: null
-- Description: Headline traffic and conversion for the reporting week against last week and the prior-12-week average, with Pet Circle sessions and all-business-line sessions side by side. Reads online__session, reference__calendar_4_4_5_week.

WITH cal AS (
  SELECT week_start_date, week_end_date FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
),
r AS (
  SELECT week_start_date AS ws, week_end_date AS we FROM `petcircle-warehouse-cloud.business_layer.reference__calendar_4_4_5_week`
  WHERE is_latest_merch_complete_week = TRUE
),
wk AS (
  SELECT c.week_start_date, c.week_end_date, DATE_DIFF(r.ws, c.week_start_date, DAY) / 7 AS k
  FROM cal c CROSS JOIN r
  WHERE c.week_start_date BETWEEN DATE_SUB(r.ws, INTERVAL 84 DAY) AND r.ws
),
mj AS (
  SELECT wk.k, wk.week_start_date, wk.week_end_date, SUM(m.session_count) AS s, SUM(m.session_count_has_converted) AS o
  FROM `petcircle-warehouse-cloud.business_layer.online__session` m
  JOIN wk ON m.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE m.bot_likelihood_category = 'Likely Human' AND m.business_line = 'Pet Circle'
    AND m.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
  GROUP BY 1, 2, 3
),
os AS (
  SELECT wk.k,
    SUM(s.session_count_all) AS s_all,
    SUM(IF(s.digital_platform_type = 'Mobile App', s.session_count_all, 0)) AS s_app,
    SUM(IF(s.digital_platform_type = 'Mobile App', 0, s.session_count_all)) AS s_web,
    COUNT(DISTINCT s.user_device_id) AS uv,
    SUM(s.page_view_count_all) AS pv
  FROM `petcircle-warehouse-cloud.business_layer.online__session` s
  JOIN wk ON s.session_start_date BETWEEN wk.week_start_date AND wk.week_end_date
  WHERE s.bot_likelihood_category = 'Likely Human'
    AND s.session_start_date BETWEEN (SELECT DATE_SUB(ws, INTERVAL 84 DAY) FROM r) AND (SELECT we FROM r)
  GROUP BY 1
),
t AS (SELECT * FROM mj WHERE k = 0),
lw AS (SELECT * FROM mj WHERE k = 1),
b AS (
  SELECT COUNT(*) AS n, SUM(s) AS s, SUM(o) AS o, MIN(week_start_date) AS b0, MAX(week_end_date) AS b1
  FROM mj WHERE k BETWEEN 1 AND 12
),
ot AS (SELECT * FROM os WHERE k = 0),
ol AS (SELECT * FROM os WHERE k = 1),
ob AS (SELECT COUNT(*) AS n, SUM(s_all) AS s_all FROM os WHERE k BETWEEN 1 AND 12)
SELECT
  FORMAT_DATE('%F', r.we) AS week_end,
  t.s AS sessions,
  lw.s AS sessions_lw,
  ROUND(SAFE_DIVIDE(t.s, lw.s) - 1, 4) AS sessions_vs_lw_pct,
  ROUND(SAFE_DIVIDE(b.s, b.n), 1) AS sessions_l12w,
  ROUND(SAFE_DIVIDE(t.s, SAFE_DIVIDE(b.s, b.n)) - 1, 4) AS sessions_vs_l12w_pct,
  ROUND(100 * SAFE_DIVIDE(t.o, t.s), 4) AS cvr,
  ROUND(100 * SAFE_DIVIDE(b.o, b.s), 4) AS cvr_l12w,
  ROUND(100 * SAFE_DIVIDE(t.o, t.s) - 100 * SAFE_DIVIDE(b.o, b.s), 4) AS cvr_vs_l12w_pp,
  t.o AS orders,
  ROUND(SAFE_DIVIDE(b.o, b.n), 1) AS orders_l12w,
  ROUND(SAFE_DIVIDE(t.o, SAFE_DIVIDE(b.o, b.n)) - 1, 4) AS orders_vs_l12w_pct,
  ot.s_all AS sessions_all,
  ol.s_all AS sessions_all_lw,
  ROUND(SAFE_DIVIDE(ot.s_all, ol.s_all) - 1, 4) AS sessions_all_vs_lw_pct,
  ROUND(SAFE_DIVIDE(ob.s_all, ob.n), 1) AS sessions_all_l12w,
  ROUND(SAFE_DIVIDE(ot.s_all, SAFE_DIVIDE(ob.s_all, ob.n)) - 1, 4) AS sessions_all_vs_l12w_pct,
  ot.s_all - t.s AS sessions_gap,
  ot.s_web AS web_sessions,
  ot.s_app AS app_sessions,
  ot.uv AS unique_visitors,
  ROUND(SAFE_DIVIDE(ot.uv, ol.uv) - 1, 4) AS unique_visitors_vs_lw_pct,
  ot.pv AS page_views,
  ROUND(SAFE_DIVIDE(ot.pv, ol.pv) - 1, 4) AS page_views_vs_lw_pct,
  b.n AS l12w_weeks,
  FORMAT_DATE('%F', b.b0) AS l12w_start,
  FORMAT_DATE('%F', b.b1) AS l12w_end
FROM r CROSS JOIN t CROSS JOIN lw CROSS JOIN b CROSS JOIN ot CROSS JOIN ol CROSS JOIN ob
